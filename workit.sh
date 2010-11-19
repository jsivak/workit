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

# Normalize the directory name in case it includes 
# relative path components.
# this broke hard for some reason so forget normalizing for now. 
# it's probably some sort of subshell thing again, but 
# for now just leave it be and look it up later
# for ((i=1;i<=${#WORKIT_DIRS};i++)); do
#     rpath=$WORKIT_DIRS[$i]
#     echo $rpath
#     WORKIT_DIRS[$i]=$(/bin/zsh -c 'cd "$rpath"; pwd')
# done
# export WORKIT_DIRS

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
        echo  "${proj_list[0]}"
        return 0
    else
        select item in $proj_list
        do
            case "$item" in
                *)
                echo "$item"
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

# Create a new project, in the WORKIT_DIRS.
#
# Usage: mkworkit [options] PROJNAME
function mkworkit () {
    verify_workit_home || return 1

    if [[ "$1" == "" ]]; then
        echo -e "\nUsage: mkworkit [project_name]\n"
        return 1
    fi

    workit_home_count=${#WORKIT_DIRS[*]}

    if [ $workit_home_count -gt 1 ]
    then
        select proj_path in ${WORKIT_DIRS[@]}
        do
            case "$proj_path" in
                *)
                break
                ;;
            esac
        done
    else
        proj_path=$WORKIT_DIRS
    fi

    eval "projname=\$$#"

    proj_workit_path="$proj_path/$projname"
    SCRIPT_PATH=$( build_workit_script_path "$proj_workit_path" )

    # test for existing proj dir, if not create it, otherwise add 
    # the post* script files to the existing dir
    if [ ! -d $SCRIPT_PATH ]
    then
        (cd "$proj_path" &&
        mkdir -p "$SCRIPT_PATH"
        )
    else
        (cd "$SCRIPT_PATH")
    fi

    if [[ ! -d $SCRIPT_PATH ]]; then
        mkdir -p "$SCRIPT_PATH"
    fi

    touch "${SCRIPT_PATH}/activate" &&
    touch "${SCRIPT_PATH}/deactivate" &&
    chmod +x "${SCRIPT_PATH}/activate" "${SCRIPT_PATH}/deactivate" 

    # If they passed a help option or got an error from virtualenv,
    # the environment won't exist.  Use that to tell whether
    # we should switch to the environment and run the hook.
    [ ! -d "$proj_path/$envname" ] && return 0
    workit "$projname"
    #workit_source_hook "$WORKIT_DIRS/postmkvirtualenv"
}

# List the available environments.
function show_workit_projects () {
    verify_workit_home || return 1
    # NOTE: DO NOT use ls here because colorized versions spew control characters
    #       into the output list.
    all=()
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

	if [ "$PROJ_NAME" = "" ]
    then
        show_workit_projects
        return 1
    fi

	PROJ_PATH=$( verify_workit_project "$PROJ_NAME" )
    if [ ! -d $PROJ_PATH ]
    then
        return 1
    else
        export PROJ_PATH
    fi

    verify_workit_home || return 1

    # Deactivate any current environment "destructively"
    # before switching so we use our override function,
    # if it exists.
    type workdone >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        workdone
    fi
    
    cd $PROJ_PATH
    SCRIPT_PATH=$( build_workit_script_path "$PROJ_PATH" )

    eval 'function workdone () {
        workit_source_hook "'$SCRIPT_PATH'/deactivate"
    }'
    
    workit_source_hook "$SCRIPT_PATH/activate"
    
	return 0
}

function build_workit_script_path () {
    base_path="$1"
    WORKIT_HOST=$(hostname -s)
    SCRIPT_PATH="$base_path/.workit/${USERNAME}/${WORKIT_HOST}"
    echo $SCRIPT_PATH
}

#
# Set up tab completion.  (Adapted from Arthur Koziel's version at 
# http://arthurkoziel.com/2008/10/11/virtualenvwrapper-bash-completion/)
# 
if [[ $CUR_SHELL == "zsh" ]]; then
    compctl -g "`show_workit_projects`" workit 
fi
