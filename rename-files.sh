#!/bin/env bash

# TODO:
# - Add -E or -r option to use regex using the =~ operator. Support sed-style
#   escapes, \1 through \9, maybe \0 or \& for the whole match.
# - incorporate rename-titlecase and rename-nameswap
#   use long opts --titlecase, --nameswap; needs longopts parsing, and new cases in _rnf_def_nfn
# - write examples like those in the manpages for rename and rename.ul

# dependencies
_deps=( docsh err_msg vrb_msg )

# handy alias
# - This only takes effect if the file is sourced, otherwise add the alias to
#   e.g. ~/.bashrc.
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

    # cleanup routine
    local _subfuncs=()
    trap '
        unset -f "${_subfuncs[@]}"
        trap - return
    ' RETURN

    local _verb=1
    local mv_cmd=( /bin/mv )

    # import supporting funcs
    import_func -l _rnf_do_rename \
        || return

    # parse options and posnl args
    local noexec \
        match_mode=s  # s, g, #, or %
    local ptrn repl ofns
    _rnf_parse_args "$@" || return
    shift $#

    # check patsub shell option
    local _patsub_off
    _rnf_patsub -c

    # loop over (original) filenames
    local ofn
    for ofn in "${ofns[@]}"
    do
        # check and split ofn
        local obn odn
        _rnf_chk_ofn \
            || return

        # define new filename
        local nfn nfn1 obn_str nbn_str
        _rnf_def_nfn \
            || continue

        # print differences
        # - regardless of noexec, since the mv prompt is not very informative
        _rnf_print_diff

        _rnf_do_rename \
            || return
    done

    [[ -v noexec ]] \
        && printf >&2 '%s\n' "  (dry run, no files were modified)"

    # restore patsub
    _rnf_patsub -r
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
