#!/bin/env bash

# TODO:
# - Add -E or -r option to use regex using the =~ operator. Support sed-style
#   escapes, \1 through \9, maybe \0 or \& for the whole match.
# - incorporate rename-titlecase and rename-nameswap
# - write examples like those in the manpages for rename and rename.ul
# - print the result of all renaming operations first, then ask for confirmation on the lot

# dependencies
_deps=( docsh err_msg )

# handy alias (only if the file is sourced)
alias rnf='rename-files'

rename-files() {

    : "Rename files using substring or pattern replacement

        Usage

            rename-files [opts] {ptrn} {repl} {file-name ...}

        In the indicated file-names, a match to 'ptrn' is replaced with the 'repl'
        string. The default command used to rename the files is '/bin/mv -vi'. The -v
        option causes mv to print a helpful string, and the -i option causes mv to
        request confirmation before overwriting a file.

        With the -i (interactive) flag in effect, a file is only overwritten if the user
        provides a string starting with y or Y at the confirmation prompt. The file will
        be skipped if the reply is any other string, such as 'n' or an empty string. If
        the user hits ^C at the prompt, the program will abort.

        Options

          -b : make a backup copy before overwriting a file (conflicts with -n)
          -f : overwrite files without prompting
          -i : prompt for overwriting files (default)
          -n : do not overwrite existing files

          -g : replace all 'ptrn' matches in a filename, not only the first
          -# : match only at the start of the filename
          -% : match only at the end of the filename

          -p : only print the renaming operation, do not touch the files
          -q : do not print filenames as they are renamed

        The -i, -f, and -n options mutually exclusive, and only the final one provided
        on the command line takes effect. The same is true for the -g, -#, and -%
        options. For details on the backup file naming scheme refer to the mv manpage.

        Pattern matching details

          - The 'ptrn' argument is interpreted similarly to a glob pattern by the
            shell. Refer to 'Pattern Matching' in the Bash manpage for syntax details.
          - The longest possible match to 'ptrn' is replaced.
          - The 'patsub_replacement' shell option is enabled. Any non-esacped instances
            of '&' in 'repl' are replaced with the matching portion of 'ptrn'. To print
            a literal '&', use '\&'. The 'repl' string is not subject to other shell
            expansions after it has been passed as an argument.

        Notes

          - Operates only on file basenames. Moving files among directories is not
            supported.
          - Filenames that don't match 'ptrn' are ignored.
          - Use an empty 'repl' argument to remove 'ptrn'.
          - If only the case of the file-name changes in the renaming operation, a
            two-step renaming process is used for safety on case-insenstive filesystems.

        Alternatives

          - For more robust treatment of regular expressions, use the perl function
            'rename' from the repos.

          - For simple string replacement on a single file, including addition and
            removal, use the shell's brace expansion instead. E.g.:

              touch file_abc.ext
              mv -vi file_{abc,def}.ext  # replace 'abc' with 'def'
              mv -vi file_def{,ghi}.ext  # add 'ghi'
              mv -vi file_{def,}.ext     # remove 'def'
    "

    [[ $# -eq 0  || $1 == @(-h|--help) ]] \
        && { docsh -TD; return; }

    local mv_cmd=( /bin/mv )

    # options
    local _b _v noexec \
        ow_mode match_mode

    # posnl args
    local ptrn repl ofns

    _rnf_parse_args "$@" \
        || return
    shift $#

    # check patsub option
    local _patsub_off
    _rnf_patsub -c

    # loop over filenames
    local ofn
    for ofn in "${ofns[@]}"
    do
        # check and split ofn
        local obn odn
        _rnf_chk_ofn \
            || return

        # perform the filename substitution
        local nbn nfn nfn1 obn_str nbn_str
        _rnf_def_nfn \
            || continue

        # print regardless of noexec, since the mv prompt is not very informative
        _rnf_print_diff

        _rnf_do_rename \
            || return
    done

    [[ -v noexec ]] \
        && printf '%s\n' "  (dry run, no files were modified)"

    # restore patsub
    _rnf_patsub -r

    return 0
}

_rnf_parse_args() {

    # Defaults
    _v=1          # verbosity
    ow_mode=i     # f, i, or n
    match_mode=s  # s, g, #, or %

    # Parse CLI args
    local flag OPTARG OPTIND=1
    while getopts ':bfing#%pq' flag
    do
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

if [[ $0 == "${BASH_SOURCE[0]}" ]]
then
    # Script was executed, not sourced

    # import dependencies and run
    source "${BASH_FUNCLIB:-"$HOME/.bash_lib"}/import_func.sh" \
        || exit 9

    import_func "${_deps[@]}" \
        || exit

    rename-files "$@" \
        || exit

else
    # sourced script should have import_func in the environment
    import_func "${_deps[@]}" \
        || return

    unset _deps
fi
