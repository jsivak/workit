# Functions to load working code projects
#
# heavily influenced/copied from Doug Hellmanns, virtualenvwrapper
# http://bitbucket.org/dhellmann/virtualenvwrapper/overview/
#
# set -x

# In order to support for multiple users with their own scripts in the same project
# we are going to store all workit processing scripts in the following
# directory structure:
#   [project name]/.workit/[username]/[hostname]
#
# Where [project name] is your project
#       [username] is the system username you logged in with
#       [hostname] is the hostname of the system
#
# This allows a team of developers to work on the same project and have
# differnt activation scripts to suit their own needs

# Shell check; mitechie LOVES zsh, so we need to accommodate. :)
CUR_SHELL="$( ps | grep $$ | awk '{ print $4 }' )"

# TODO
# virtualenv sets the VIRTUAL_ENV system variable, need to replicate a bit

# source the helper script functions
# assuming its in the same dir as this file
#BASEDIR=`dirname $0`
#source $BASEDIR/process_functions.sh

# You can override this setting in your .zshrc/.bashrc
if [[ "$WORKIT_DIRS" == "" ]]
then
    WORKIT_DIRS=( "$HOME/src" "$HOME/configs" "$HOME/gitbox" )
	export WORKIT_DIRS
fi

### Functions

# Verify that the WORKON_HOME directory exists
function verify_workit_home () {
    #for zpath in ${WORKIT_DIRS[@]}; do
    #    if [ ! -d "$zpath" ]
    #    then
    #        echo "WARNING: projects directory '$zpath' does not exist." >&2
    #    fi
    #done
    return 0
}

# Verify that the requested project exists
function verify_workit_project () {
    env_name="$1"
    proj_count=0
    proj_list=()

    # Sanity chcks
    if [[ "${USER}" == "" ]]; then
        echo -e "Can't determine user name based on USER environment variable."
        return 1
    fi
    WORKIT_HOST="$(hostname -s)"
    if [[ "${WORKIT_HOST}" == "" ]]; then
        echo -e "Can't determine hostname based on 'hostname -s' command."
        return 1
    fi

    for zpath in ${WORKIT_DIRS[@]}; do
        target_path="$zpath/$env_name"
        if [[ -d $target_path ]]; then
            #proj_list+=("$target_path")
            # BASH version 3 doesn't like the += operator
            proj_list=($proj_list "$target_path")
            ((proj_count+=1))
        fi
    done

    if [[ $proj_count -eq 1 ]]; then
        RET_VAL="${proj_list[0]}"
        return 0
    else
        select item in $proj_list
        do
            case "$item" in
                *)
                RET_VAL="$item"
                break
                ;;
            esac
        done
        return 0
    fi
}


# Verify that the active project exists
function verify_active_project () {
    if [ ! -n "${PROJECT_DIR}" ] || [ ! -d "${PROJECT_DIR}" ]
    then
        echo "ERROR: no project active, or active project is missing" >&2
        return 1
    fi
    return 0
}

# source the pre/post hooks
# NOTE: This function expects the FULL path to the script
function workit_source_hook () {
    scriptname="$1"

    if [ -f "$scriptname" ]
    then
        source "$scriptname"
    fi
}


# run the pre/post hooks
function workit_run_hook () {
    scriptname="$1"
    shift
    if [ -x "$scriptname" ]
    then
        "$scriptname" "$@"
    fi
}

# Create a new project, either based on a WORKIT_DIRS
# or directly specified.
#
# Usage: mkworkit [ directory_in_WORKIT_DIRS | path_to_directory ]
function mkworkit () {
    if [[ "$1" == "" ]]; then
        echo -e "\nUsage: mkworkit [ directory_in_WORKIT_DIRS | path_to_directory ]\n"
        return 1
    fi

    # check if we're given a direct path
    if [[ "$1" == */* || "$1" == "." || "$1" == ".." ]]; then
        DIRECT=1

        canonpath "$1"
        PROJ_PATH="$RET_VAL"

        if [[ -d "$PROJ_PATH" ]]; then
            echo "workit: mkworkit setting up on direct path $PROJ_PATH"
        else
            echo "workit: Can't find $PROJ_PATH"
            return 1
        fi
    else
        DIRECT=0
        verify_workit_home || return 1

        workit_home_count=${#WORKIT_DIRS[*]}

        if [ $workit_home_count -gt 1 ]
        then
            OLD_IFS="$IFS"
            # Remove the space from the IFS so we can show a "None / Cancel" option
            IFS=$'\t\n'
            DIR_LIST=('None / Cancel')
            DIR_LIST+=("${WORKIT_DIRS[@]}")
            select PROJ_PATH in ${DIR_LIST[@]}
            do
                case "$PROJ_PATH" in
                    "None / Cancel")
                        IFS=$OLD_IFS
                        return 0
                        ;;
                    *)
                        break
                        ;;
                esac
            done
            IFS="$OLD_IFS"
        else
            PROJ_PATH=$WORKIT_DIRS
        fi

        PROJ_NAME="$1"
        PROJ_PATH="$PROJ_PATH/$PROJ_NAME"
        echo "workit: mkworkit setting up $PROJ_NAME from WORKIT_DIRS path [${PROJ_PATH%/*}]"
    fi

    build_workit_script_path "$PROJ_PATH"
    SCRIPT_PATH=$RET_VAL

    # test for existing proj dir, if not create it, otherwise add
    # the script files to the existing dir
    if [[ ! -d $SCRIPT_PATH ]]; then
        mkdir -p "$SCRIPT_PATH"
        echo "workit: New scripts added to $SCRIPT_PATH in $PROJ_PATH"
    else
        echo "workit: Scripts already exist at $SCRIPT_PATH in $PROJ_PATH"
    fi

    FILES="activate deactivate"
    for FILE in $FILES; do
        if [[ ! -f "${SCRIPT_PATH}/$FILE" ]]; then
            touch "${SCRIPT_PATH}/$FILE"
        fi
        if [[ ! -x "${SCRIPT_PATH}/$FILE" ]]; then
            chmod +x "${SCRIPT_PATH}/$FILE"
        fi
    done

    # Now actually switch/workit into our new project
    if [[ $DIRECT == 0 ]]; then
        workit "$PROJ_NAME"
    else
        workit "$PROJ_PATH"
    fi

}

# List the available environments.
function show_workit_projects () {
    verify_workit_home || return 1
    # NOTE: DO NOT use ls here because colorized versions spew control characters
    #       into the output list.
    # Handle case where we just want to see the contents of 1 specified
    # directory.
    if [[ "$1" != "" ]]; then
        tpath=$1
        echo -e "Workit directory ${tpath}:"
        echo -e "----------------------------------------"
        if [[ -d $tpath ]]; then
            ls --color=auto -C $tpath
        else
            echo -e "Directory ${tpath} doesn't exist"
        fi
        echo -e "\n"
    else
        for tpath in ${WORKIT_DIRS[@]}; do
            echo -e "Workit directory ${tpath}:"
            echo -e "----------------------------------------"
            if [[ -d $tpath ]]; then
                ls --color=auto -C $tpath
            else
                echo -e "Directory ${tpath} doesn't exist"
            fi
            echo -e "\n"
        done
    fi
}

# list the available workit home directories for adding a new project to
function show_workit_home_options () {
    verify_workit_home || return 1
    for ((i=1;i<${#WORKIT_DIRS[*]};i++)); do
        proj=${WORKIT_DIRS[$i]}
        echo "$i - $proj"
    done
}

# List or change workit projects
#
# Usage: workit [environment_name]
#
function workit () {
	PROJ_NAME="$1"

    # check if a path was provided; if so then just try to "workit" directly on that path
    if [[ "$PROJ_NAME" == */* || "$PROJ_NAME" == "." || "$PROJ_NAME" == ".." ]]; then
        # Allow the current working directory to be specified.
        canonpath "$PROJ_NAME"
        PROJ_NAME="$RET_VAL"

        if [[ -d "$PROJ_NAME" ]]; then
            echo "workit: activating direct path $PROJ_NAME"
            canonpath "$PROJ_NAME"
            PROJ_PATH="$RET_VAL"
        else
            echo "workit: Can't find $PROJ_NAME"
            return 1
        fi
    else
        if [ "$PROJ_NAME" = "" ]
        then
            workit_home_count=${#WORKIT_DIRS[*]}
            if [ $workit_home_count -gt 1 ]
            then
                OLD_IFS="$IFS"
                # Remove the space from the IFS so we can show a "None / Cancel" option
                IFS=$'\t\n'
                DIR_LIST=('None / Cancel')
                DIR_LIST+=('All')
                DIR_LIST+=("${WORKIT_DIRS[@]}")
                echo "Select a directory to see available projects"
                select PROJ_PATH in ${DIR_LIST[@]}
                do
                    case "$PROJ_PATH" in
                        "None / Cancel")
                            IFS=$OLD_IFS
                            return 1
                            ;;
                        "All")
                            unset PROJ_PATH
                            break
                            ;;
                        *)
                            break
                            ;;
                    esac
                done
                IFS="$OLD_IFS"
            else
                PROJ_PATH=$WORKIT_DIRS
            fi

            show_workit_projects "$PROJ_PATH"
            return 1
        fi

        if verify_workit_project "$PROJ_NAME"
        then
            PROJ_PATH=$RET_VAL
        else
            return 1
        fi

        verify_workit_home || return 1

        echo "workit: activating $PROJ_NAME from WORKIT_DIRS path [${PROJ_PATH%/*}]"

    fi

    # Deactivate any current environment "destructively"
    # before switching so we use our override function,
    # if it exists.
    type workitdone >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        workitdone
    fi

    cd $PROJ_PATH

    # Set prompt
    OLD_PS1="$PS1"
    PS1="[workit]$PS1"

    build_workit_script_path "$PROJ_PATH"
    SCRIPT_PATH=$RET_VAL

    eval 'function workitdone () {
        workit_source_hook "'$SCRIPT_PATH'/deactivate"
        unset workitdone
        # Remote the prompt add-on
        PS1="${PS1/\[workit\]/}"
    }'

    workit_source_hook "$SCRIPT_PATH/activate"

	return 0
}

function build_workit_script_path () {
    base_path="$1"
    WORKIT_HOST=$(hostname -s)
    if [[ "${USER}" == "" ]]; then
        echo -e "Can't determine user name based on USER environment variable."
        RET_VAL=""
    else
        RET_VAL="$base_path/.workit/${USER}/${WORKIT_HOST}"
    fi
}

# from: http://snipplr.com/view/18026/canonical-absolute-path/
function canonpath ()
{
    RET_VAL=$(cd $(dirname $1); pwd -P)/$(basename $1)
}

#
# Set up tab completion.  (Adapted from Arthur Koziel's version at
# http://arthurkoziel.com/2008/10/11/virtualenvwrapper-bash-completion/)
#
if [[ $CUR_SHELL == "zsh" ]]; then
    compctl -g "`show_workit_projects`" workit
fi
