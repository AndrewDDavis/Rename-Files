_rnf_parse_args() {

    # Defaults
    _v=1          # verbosity
    ow_mode=i     # f, i, or n
    match_mode=s  # s, g, #, or %

    # Parse CLI args
    local flag OPTARG OPTIND=1
    while getopts ':bfing#%pq-:' flag
    do
        # handle long options
        split_longopt flag

        case $flag in
            ( b ) _b=1; mv_cmd+=( -b ) ;;
            ( f | i | n ) ow_mode=$flag ;;
            ( g | \# | % ) match_mode=$flag ;;
            ( p ) noexec=1 ;;
            ( q ) (( _v-- )) ;;

            ( \? ) err_msg 2 "unknown option: '-$OPTARG'"; return ;;
            ( : )  err_msg 3 "missing argument for -$OPTARG"; return ;;
        esac
    done
    shift $(( OPTIND-1 ))

    [[ -v _b  && $ow_mode == n ]] \
        && { err_msg 4 "-b and -n may not be used together"; return; }

    (( _v > 0 )) \
        && mv_cmd+=( -v )

    mv_cmd+=( -"$ow_mode" )

    ptrn=${1:?"pattern required"}
    repl=${2:?"repl required"}
    shift 2

    [[ $# -eq 0 ]] \
        && return 1

    ofns=( "$@" )
}

_rnf_patsub() {

    if [[ $1 == -c ]]
    then
        # check for patsub option
        if ! shopt -q patsub_replacement
        then
            _patsub_off=1
            shopt -s patsub_replacement
        fi

    elif [[ $1 == -r ]]
    then
        # restore patsub
        if [[ -v _patsub_off ]]
        then
            shopt -u patsub_replacement
        fi
    fi
}

_rnf_chk_ofn() {

    # check ofn, define obn, odn

    [[ -e $ofn ]] \
        || { err_msg 3 "file not found: '$ofn'; aborting..."; return; }

    obn=$( basename "$ofn" )

    # Stay with implied CWD if no '/' in ofn
    [[ $ofn == */* ]] \
        && odn=$( dirname "$ofn" )'/'

    return 0
}

_rnf_def_nfn() {

    # Define the new filename, and create stylized strings for user info

    # use bold and dim to emphasize replaced text
    # - not using _cbo from the csi_strvars function, as it's got prompt \[...\] chars
    local _bld=$'\e[1m' _rsb=$'\e[22m' \
        _dim=$'\e[2m' _rsd=$'\e[22m' \
        _rst=$'\e[0m'

    # perform the name change
    # - NB, repl is not subject to expansions beyond '&'
    case $match_mode in
        ( g )
            nbn=${obn//$ptrn/$repl}

            obn_str=${obn//${ptrn}/"${_dim}"&"${_rsd}"}
            nbn_str=${obn//${ptrn}/"${_bld}"${repl}"${_rsb}"}
        ;;
        ( \# )
            nbn=${obn/#$ptrn/$repl}

            obn_str=${obn/#${ptrn}/"${_dim}"&"${_rsd}"}
            nbn_str=${obn/#${ptrn}/"${_bld}"${repl}"${_rsb}"}
        ;;
        ( % )
            nbn=${obn/%$ptrn/$repl}

            obn_str=${obn/%${ptrn}/"${_dim}"&"${_rsd}"}
            nbn_str=${obn/%${ptrn}/"${_bld}"${repl}"${_rsb}"}
        ;;
        ( * )
            nbn=${obn/$ptrn/$repl}

            obn_str=${obn/${ptrn}/"${_dim}"&"${_rsd}"}
            nbn_str=${obn/${ptrn}/"${_bld}"${repl}"${_rsb}"}
        ;;
    esac

    [[ $nbn == "$obn" ]] \
        && return 1

    # check whether old and new differ only in case
    [[ ${nbn@L} == "${obn@L}" ]] \
        && nfn1="${odn-}__rn_tmp__${nbn}"

    nfn="${odn-}${nbn}"
}

_rnf_do_rename() {

    [[ -v noexec ]] \
        && return 0

    if [[ -v nfn1 ]]
    then
        # use a 2-step rename if necessary, on case-insensitive filesystems (macOS)
        err_msg i "case-difference only, using 2-step rename for safety"

        "${mv_cmd[@]}" "$ofn" "$nfn1" \
            && "${mv_cmd[@]}" "$nfn1" "$nfn"
    else
        "${mv_cmd[@]}" "$ofn" "$nfn"

    fi  || {
            # check mv return status
            # - treats $?=1 as OK: can happen on declined overwrite or permission error
            # - treats $?=130 as error: user hit Ctrl-C at overwrite prompt
            local rs=$?
            if (( rs < 2 ))
            then
                return 0
            else
                err_msg 6 "mv returned status code $rs; aborting..."
                return
            fi
        }
}

_rnf_print_diff() {

    # print info strings on renaming op
    printf '   %s\n-> %s\n' \
        "${odn-}$obn_str" \
        "${odn-}$nbn_str"

    # print a diff line to highlight changed chars with ^^ ^   ^^
    # - really it should just be under dim areas of ofn or bold areas of nfn
    local a b ch_chars=''
    for (( i=0; i<${#ofn}; i++ ))
    do
        a=${ofn:i:1}
        b=${nfn:i:1}
        if [[ $a == "$b" ]]
        then
            ch_chars+=' '
        else
            ch_chars+='^'
        fi
    done
    printf '   %s\n\n' "$ch_chars"

    # considered using diff instead
    # - regular patch output seems to work better than word-diff
    #   command git diff --no-index --word-diff -U0 --color \
    # command diff -U0 --color=auto \
    #     <( printf '%s\n' "$ofn" ) \
    #     <( printf '%s\n' "$nfn" ) \
    #     | diffr \
    #     | tail -n2
}
