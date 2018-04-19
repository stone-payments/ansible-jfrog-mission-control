#!/bin/bash

export JFMC_HOME="/opt/jfrog/mission-control"
export JFMC_DATA="/var/opt/jfrog/mission-control"
export JFMC_LOGS="$JFMC_DATA/logs"

export JFMC_USER={{jfmc_user}}
export JFMC_GROUP={{jfmc_group}}

export JFMC_PORT={{jfmc_port}}
export JFMC_SCHEDULER_PORT={{jfmc_scheduler_port}}
export JFMC_EXECUTOR_PORT={{jfmc_executor_port}}
export JFMC_CORE_PORT={{jfmc_core_port}}
export JFMC_SSL_CORE_PORT={{jfmc_ssl_core_port}}


export MANDATORY_PORT_LIST="JFMC_PORT JFMC_SCHEDULER_PORT JFMC_EXECUTOR_PORT JFMC_CORE_PORT JFMC_SSL_CORE_PORT"

export INSIGHT_SSL_URL=https://localhost:$JFMC_SSL_CORE_PORT
export INSIGHT_URL=http://localhost:$JFMC_CORE_PORT
export JFI_HOME_CORE="${JFMC_DATA}/jfi-core"
export CORE_URL="http://localhost:$JFMC_CORE_PORT"
export SCHEDULER_URL="http://localhost:$JFMC_SCHEDULER_PORT/schedulerservice"
export EXECUTOR_BASE_URL="http://localhost:$JFMC_EXECUTOR_PORT"
export EXECUTOR_URL="http://localhost:$JFMC_EXECUTOR_PORT/executorservice"
export JFMC_URL="http://localhost:$JFMC_PORT"

EXTERNALIZE_MONGO="{{jfmc_externalize_mongodb}}"

POSTGRES_HOME_DEFAULT=/var/opt/postgres
POSTGRES_PATH="/opt/PostgreSQL/9.6/bin"
POSTGRES_ROOT_USER_ID="{{jfmc_postgres_root_user_id}}"
POSTGRES_ROOT_USER_PWD="{{jfmc_postgres_root_user_pwd}}"
POSTGRES_SERVICE="postgresql-9.6"
POSTGRES_OMNI_DB="{{jfmc_postgres_omni_db}}"
POSTGRES_USER="{{jfmc_postgres_user}}"
POSTGRES_PWD="{{jfmc_postgres_pwd}}"

getPostgresDefaults() {
    JFMC_POSTGRES_PORT={{jfmc_postgres_port}}
    POSTGRESDB_HOST="localhost"
    QUARTZ_DB_URL="$POSTGRESDB_HOST:$JFMC_POSTGRES_PORT"
}

getMongoDefaults() {
    export JFMC_MONGO_PORT={{jfmc_mongo_port}}
    export SPRING_DATA_MONGODB_PORT="$JFMC_MONGO_PORT"
    export SPRING_DATA_MONGODB_HOST="{{jfmc_spring_data_mongodb_host}}"
    export MONGODB_HOST="$SPRING_DATA_MONGODB_HOST"
    export MONGO_URL="$MONGODB_HOST:$JFMC_MONGO_PORT"
    export MONGODB_USERNAME="{{jfmc_mongodb_username}}"
    export MONGODB_PASSWORD="{{jfmc_mongodb_password}}"
}

getElasticSearchDefaults() {
    ELASTIC_ADDRESS="{{jfmc_elastic_address}}"
    JFMC_ELASTIC_PORT={{jfmc_elastic_port}}
    JFMC_ELASTIC_COMMUNICATION_NODE_PORT={{jfmc_elastic_communication_node_port}}
    ELASTIC_SEARCH_URL="$ELASTIC_ADDRESS:$JFMC_ELASTIC_PORT"
    ELASTIC_CLUSTER_NAME="{{jfmc_elastic_cluster_name}}"
    ELASTIC_COMMUNICATION_NODE_URL="{{jfmc_elastic_host}}:$JFMC_ELASTIC_COMMUNICATION_NODE_PORT"
    ELASTIC_SEARCH_USERNAME="{{jfmc_elastic_search_username}}"
    ELASTIC_SEARCH_PASSWORD="{{jfmc_elastic_search_password}}"
}

{% raw %}
# ------------------------------------------------------------------------------
# Utilities functions
# ------------------------------------------------------------------------------

#Adding a small timeout before a read ensures it is positioned correctly in the screen
read_timeout=1

checkSELinux() {
     # Check SELinux status for mongoDB service to run
     if [ -f /etc/selinux/config ]; then
        selinux_mode=$(getenforce | tr '[:upper:]' '[:lower:]' 2>/dev/null)

        if [ ! -z ${selinux_mode} ] && [ ! "${selinux_mode}" == "" ]; then
            echo; log "SELinux policy status is [${selinux_mode}]"

            case "$selinux_mode" in
                "permissive"|"disabled")
                    ;;
                "enforcing")
                    if [[ "${DIST}" =~ RedHat|CentOS ]] && [ "${DIST_VER}" == "6" ]; then
                        log "No need for special SElinux configuration in RedHat/CentOS 6"
                    else
                        MONGO_PORT_RULE=$(semanage export | grep "mongod_port_t -p tcp 27017")
                        if [[ -z "$MONGO_PORT_RULE" ]]; then
                            echo; log "SELinux is in enforce mode and port rule named mongod_port_t for tcp port 27017 not found."
                            errorExit "To continue with the installation, you must set a new SELinux policy rule to allow mongodb to run."
                        else
                            echo; log "SELinux mongodb port rule found. '$MONGO_PORT_RULE'"
                        fi
                    fi
                    ;;
            esac
        fi
     fi
}

#Copy file or directory from source to destination
copyItem(){
    local item=$1
    local sourcePath=$2
    local destPath=$3
    local filePermission=$4

    if [ ! -f "$destPath/$item" ] || [ ! -d "$destPath/$item" ]; then
       mkdir -p "$destPath" && \
       cp -fr "$sourcePath/$item" "$destPath/$item" || errorExit "$item could not be copied"
    fi

    [ ! -z "$filePermission" ] && [ "$filePermission" != "" ] && chmod $filePermission "$destPath"
}

# Assign new port number to the variables passed and update env variables file - setenv.sh
# Accepts one parameter which needs to be a string with space delimited list of variable names
# Expects variables to be assigned with current port numbers
# Usage : assignNewPorts "JFMC_PORT JFMC_EXECUTOR_PORT"
assignNewPorts() {
    if [[ -z "$1" || "$1" == "" ]]; then
        return
    fi
    local PORT_ENV_LIST=($1)
    local PORT_KEY_ALLOCATED_LIST=
    local PORT_VALUE_ALLOCATED_LIST=
    local new_port=

    for port_key in "${PORT_ENV_LIST[@]}"
    do
        # Get the value associated with this variable (indirect reference)
        port_value=${!port_key}
        [ ! -z "$port_value" ] && getUserInput "Please enter an unused port number between 0 to 65535, this will be used as an alternative to [ $port_value ] "
        new_port=$users_choice
        [ $(isPortAllocated "$new_port") ] && new_port="NOT_FREE"
        
        # Prompt user for port number until it passes validation criteria
        while ! [[ "$new_port" =~ ^[0-9]+$ ]] || ! [ "$new_port" -ge 0 -a "$new_port" -le 65535 ]; do
            [ ! -z "$port_value" ] && getUserInput "Please enter an unused port number between 0 to 65535, this will be used as an alternative to [ $port_value ] "
            new_port=$users_choice
            [ $(isPortAllocated "$new_port") ] && new_port="NOT_FREE"
        done

        log "Updating [ $port_value ] with [ $new_port ]"
        eval $port_key=$new_port

        if [[ ! -f "$JFMC_MASTER_ENV" && ! -f "$JFMC_MODIFIED_ENV" ]]; then
            echo '#!/bin/bash' > "$JFMC_MODIFIED_ENV"
        fi

        addToEnvFile "$port_key"
    done
}

# Add or replace a property in provided properties file
addOrReplaceProperty() {
    local propertyName=$1
    local propertyValue=$2
    local propertiesPath=$3

    # Return if any of the inputs are empty
    [[ -z "$propertyName"   || "$propertyName"   == "" ]] && return
    [[ -z "$propertyValue"  || "$propertyValue"  == "" ]] && return
    [[ -z "$propertiesPath" || "$propertiesPath" == "" ]] && return

    grep "^${propertyName}=" ${propertiesPath} > /dev/null 2>&1
    [ $? -ne 0 ] && echo -e "\n${propertyName}=changeme" >> ${propertiesPath}
    sed -i -e "s|^${propertyName}=.*$|${propertyName}=${propertyValue}|g;" ${propertiesPath}
}

# Check if provided port is allocated
isPortAllocated() {
    local port_value=$1
    if [[ -z "$port_value" || "$port_value" == "" ]]; then
        echo -n ""
    fi

    isInstalled "net-tools"
    if [[ $? -ne 0 ]]; then
        log "Package net-tools is not installed, skipping port validation"
        echo -n ""
    fi

    if netstat -ano|grep ":$port_value "|grep LISTEN >&6; then
        echo -n "yes"
    fi
}

# Validate if port is available for use
# Accepts one parameter which needs to be a string with space delimited list of variable names
# Expects variables to be assigned with port numbers to be validated
# If exit type is error, user will be prompted to assign alternate port numbers
# usage : validatePorts "JFMC_PORT JFMC_EXECUTOR_PORT"
validatePorts() {
    if [[ -z "$1" || "$1" == "" ]]; then
        return
    fi

    local PORT_ENV_LIST=($1)
    local PORT_KEY_ALLOCATED_LIST=
    local PORT_VALUE_ALLOCATED_LIST=
    local exitType=${2:-error}

    for port_key in "${PORT_ENV_LIST[@]}"
    do
        # Get the value associated with this variable (indirect reference)
        port_value=${!port_key}
        log "validating port : $port_value" >&6

        if [[ ! -z "${port_value}" && "${port_value}" != "" && $(isPortAllocated "$port_value") ]] ; then
            PORT_KEY_ALLOCATED_LIST="$PORT_KEY_ALLOCATED_LIST $port_key"
            PORT_VALUE_ALLOCATED_LIST="$PORT_VALUE_ALLOCATED_LIST $port_value"
        fi
        log "ok" >&6
    done

    if [[ ! -z "$PORT_VALUE_ALLOCATED_LIST" || "$PORT_VALUE_ALLOCATED_LIST" != ""  ]]; then
        if [[ "$exitType" == "warning" ]]; then
            warn "Ports [ $PORT_VALUE_ALLOCATED_LIST ] are in use. Installer will still attempt to continue"
            
            getUserChoice "Do you want to continue [Y/n]" "y n Y N" "y"
            if [[ $users_choice == "n" || $users_choice == "N" ]]; then
                exit 0
            fi
        else
            getUserChoice "Ports [ $PORT_VALUE_ALLOCATED_LIST ] are in use. Installer will not be able to continue. Do you want to assign alternative ports [Y/n]" "y n Y N" "y"
            if [[ $users_choice == "n" || $users_choice == "N" ]]; then
                exit 1
            fi
            assignNewPorts "$PORT_KEY_ALLOCATED_LIST"
        fi
    fi
}

getLinuxDistribution() {
    # Make sure running on Linux
    if [ $(uname -s) != "Linux" ]; then errorExit "The installation only supports Linux"; fi

    # Find out what Linux distribution we are on
    DIST=

    cat /etc/*-release | grep -i Red >&6
    if [ $? -eq 0 ]; then DIST=RedHat; fi

    # OS 6.x
    cat /etc/issue.net | grep Red >&6
    if [ $? -eq 0 ]; then DIST=RedHat; fi

    # OS 7.x
    cat /etc/*-release | grep -i centos >&6
    if [ $? -eq 0 ]; then DIST=CentOS; DIST_VER="7"; fi

    # OS 7.x
    grep -q -i "release 7" /etc/redhat-release >&6 2>&1
    if [ $? -eq 0 ]; then DIST_VER="7"; fi

    # OS 6.x
    grep -q -i "release 6" /etc/redhat-release >&6 2>&1
    if [ $? -eq 0 ]; then DIST_VER="6"; fi

    cat /etc/*-release | grep -i Red | grep -i 'VERSION=7' >&6
    if [ $? -eq 0 ]; then DIST=RedHat; DIST_VER="7"; fi

    cat /etc/*-release | grep -i debian >&6
    if [ $? -eq 0 ]; then DIST=Debian; fi

    cat /etc/*-release | grep -i ubuntu >&6
    if [ $? -eq 0 ]; then DIST=Ubuntu; fi
}

#Append a line of string if it does not exist
appendString(){
    local stringFound
    local targetString=$1
    local targetFile=$2

    if [ -z "$targetString" ] || [ -z "$targetFile" ];
    then 
        errorExit "Target string or file not provided for append operation"
    fi

    # append string only if its not found
    stringFound=$(isStringFound "$targetFile" "$targetString")
    [[ $stringFound == *"no"* ]] && echo "$targetString" >> "$targetFile"
}

#check if the script can be run
checkLinuxDistribution() {
    checkRoot

    getLinuxDistribution

    # If non set - not supported
    if [ -z "$DIST" ]; then errorExit "Linux distribution type not supported"; fi

    # Make sure we are running the correct platform's installer
    echo $(basename $0) | grep -i ${DIST} >&6
    if [ $? -ne 0 ]; then errorExit "You cannot run $(basename $0) on a $DIST Linux distribution!"; fi

    cd ${INSTALLER_DIR}

    # Remove LC_CTYPE from env, fix for mac users (via ssh), which execute the command with sudo
    if [ ! -z ${LC_CTYPE} ]; then
        LC_CTYPE_BACKUP=${LC_CTYPE}
        unset LC_CTYPE
    fi
}

# Utility method to display warnings
warn() {
    echo ""
    echo -e "\033[33m $1 \033[0m"
    echo ""
}

# This function prints the echo with color.
#If invoked with a single string, treats it as INFO level
#Valid inputs for the second parameter are DEBUG and INFO
log() {
    #Get the intended log level
    INPUT_LOG_LEVEL=$2
    #Default to INFO if absent
    : ${INPUT_LOG_LEVEL:="INFO"}
    #Get the configured log level. Default to INFO if absent
    : ${JFMC_LOG_LEVEL:="INFO"}
    #Display colors? Default to NO
    : ${JFMC_COLOR_LOGS:="NO"}

    #Get the final color to display the log in
    if [[ $JFMC_COLOR_LOGS == "NO" ]]
    then
        OUTPUT="$1"
    elif [[ $INPUT_LOG_LEVEL = "INFO" ]] 
    then
        OUTPUT="\033[32m $1\033[0m " 
    elif [[ $INPUT_LOG_LEVEL = "DEBUG" ]] 
    then
        OUTPUT="\033[34m $1\033[0m "    
    fi
    
    #If intended level if INFO and configured is either DEBUG or INFO, log it
    if [[ ( $INPUT_LOG_LEVEL = "INFO") &&  ( ( $JFMC_LOG_LEVEL = "INFO" ) || ( $JFMC_LOG_LEVEL = "DEBUG" ) ) ]]
    then
        echo; echo -e $OUTPUT; echo
    #If intended level if DEBUG and configured is DEBUG, log it 
    elif [[ ( $JFMC_LOG_LEVEL = "DEBUG" ) ]]
    then
        echo; echo -e $OUTPUT; echo
    fi
}

# Add a line to a file if it doesn't already exist
addLine() {
    local line_to_add=$1
    local target_file=$2
    echo "Trying to add line $1 to $2" >&6 2>&1
    cat "$target_file" | grep -F "$line_to_add" -wq >&6 2>&1
    if [ $? != 0  ]; then
        echo "Line does not exist and will be added" >&6 2>&1
        echo $line_to_add >> $target_file || errorExit "Could not update $target_file"
    fi    
}

#Print the input with additional formatting to indicate a section/title
title () {
    echo
    echo "-----------------------------------------------------"
    printf "| %-50s|\n" "$1"
    echo "-----------------------------------------------------"
}


#Print the input with additional formatting to indicate a section/title
stage () {
    echo -e "\033[34m ------------------------------------------------------------------------------------------------------------------------------- \033[0m"
    printf "                                                  \033[34m[%s]\033[0m" "$1"
    echo
}

#Print the statement along with the line number and timestamp
logPrinter() {
    echo
    DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
    if [ -z "$CONTEXT" ]
    then
        CONTEXT=$(caller)
    fi
    MESSAGE=$1
    CONTEXT_LINE=$(echo "$CONTEXT" | awk '{print $1}')
    CONTEXT_FILE=$(echo "$CONTEXT" | awk -F"/" '{print $NF}')
    printf "%s %05s %s %s\n" "$DATE_TIME" "[$CONTEXT_LINE" "$CONTEXT_FILE]" "$MESSAGE" >&6 2>&1
    CONTEXT=
}

#Display an error and exit
errorExit() {
    echo -e "\033[31mERROR: $1 \033[0m"; echo
    exit 1
}

checkRoot() {
    local USE=$(id -u -n)

    # Make sure the script is run as root
    if [ ${USE} != 'root' ]; then
        errorExit "This script must be run as root"
    fi
}


# Returned code:
#0) $1=$2
#1) $1>$2
#2) $1<$2
verComp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i
    local ver1=($1)
    local ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

# Check if string is available in a provided file
# Will echo yes or no based on result
# usage : isStringFound "sample.txt" "A sample text"
isStringFound() {
    local fileName=$1
    local targetString=$2
    local isFound="no"
    if grep -Fxq "$targetString" "$fileName" &> /dev/null
    then
        isFound="yes"
    fi
    echo $isFound
}

# Check if a tool is installed by accepting packname as a parameter
# Will return 1 if it is not installed
# usage : isInstalled "curl"
isInstalled(){
    local packName=$1
    local name=''
    local version=''
    
    arrIN=(${packName//=/ })
    packName=${arrIN[0]}

    if [ -z ${packName} ] || [ "${packName}" == "" ]
    then
        errorExit "isInstalled: missing packName value"
    fi

    case $DIST in
        CentOS|RedHat)
            name="$(rpm -qi --nosignature ${packName} 2>/dev/null | grep Name | awk -F ': ' '{print $2}')"
            version="$(rpm -qi --nosignature ${packName} 2>/dev/null | grep Version | awk -F ': ' '{print $2}' | awk '{print $1}')"
        ;;
        Debian|Ubuntu)
            name=$(dpkg-query -W -f='${binary:Package}' ${packName} 2>/dev/null)
            version=$(dpkg-query -W -f='${Version}' ${packName} 2>/dev/null)
        ;;
        *)
            errorExit "isInstalled: Distribution $DIST is not supported"
            return 1
        ;;
    esac

    # if name and version is not available consider it as not installed and return 1
    # let the caller decide what to do based on this response
    if [ -z "${name}" ] || [ "${name}" == "" ] || [ -z "${version}" ] || [ "${version}" == "" ]
    then
        return 1
    else
        return 0
    fi
}

isPackInstalled() {
    local packName=$1
    local packFile=$2
    local strictCheck=$3
    if [[ ! -f "$packFile" ]]
    then
        packFile="packages/$packFile"
    fi
    local currentName=''
    local newName=''
    local currentVer=''
    local newVer=''
    local currentRel=''
    local newRel=''

    if [[ -z "${packName}" ]] || [[ "${packName}" == "" ]] || [[ -z "${packFile}" ]] || [[ "${packFile}" == "" ]]
    then
        errorExit "isPackInstalled: missing packName\packFile value"
    fi

    case $DIST in
        CentOS|RedHat)
            currentName="$(rpm -qi --nosignature ${packName} 2>/dev/null | grep Name | awk -F ': ' '{print $2}')"
            currentVer="$(rpm -qi --nosignature ${packName} 2>/dev/null | grep Version | awk -F ': ' '{print $2}' | awk '{print $1}')"
            currentRel="$(rpm -qi --nosignature ${packName} 2>/dev/null | grep Release | awk -F ': ' '{print $2}' | awk '{print $1}')"

            newName="$(rpm -qip --nosignature ${packFile} 2>/dev/null | grep Name | awk -F ': ' '{print $2}')"
            newVer="$(rpm -qip --nosignature ${packFile} 2>/dev/null | grep Version | awk -F ': ' '{print $2}' | awk '{print $1}')"
            newRel="$(rpm -qip --nosignature ${packFile} 2>/dev/null | grep Release | awk -F ': ' '{print $2}' | awk '{print $1}')"
        ;;
        Debian|Ubuntu)
            if [[ "$strictCheck" == *"yes"* ]]; then
                # Check if this is an upgrade
                local status
                local currentState

                # get status of packname
                status=$(dpkg -l | grep "${packName}" | awk '{print $1}')
                # get second character of the response
                [[ ! -z $status ]] && currentState=${status:1:1} || currentState="Not Installed"
                
                # if currentState is 'i', consider it as installed
                if [[ "$currentState" == "i" ]]; then
                    currentName=$(dpkg-query -W -f='${binary:Package}' ${packName} 2>/dev/null)
                    currentVer=$(dpkg-query -W -f='${Version}' ${packName} 2>/dev/null)

                    newName="$(dpkg --info ${packFile} | grep Package | awk -F ': ' '{print $2}')"
                    newVer="$(dpkg --info ${packFile} | grep Version | awk -F ': ' '{print $2}')"
                else
                    return 1
                fi            
            else
                currentName=$(dpkg-query -W -f='${binary:Package}' ${packName} 2>/dev/null)
                currentVer=$(dpkg-query -W -f='${Version}' ${packName} 2>/dev/null)

                newName="$(dpkg --info ${packFile} | grep Package | awk -F ': ' '{print $2}')"
                newVer="$(dpkg --info ${packFile} | grep Version | awk -F ': ' '{print $2}')"
            fi
        ;;
        *)
            errorExit "isPackInstalled: Distribution $DIST is not supported"
            return 1
        ;;
    esac

    # currentVer: to lower, use dots
    currentVer=$(echo "${currentVer,,}" | tr - . )
    currentVer=$(echo "${currentVer,,}" | tr _ . )

    # currentRel: to lower, use dots
    currentRel=$(echo "${currentRel,,}" | tr - . )
    currentRel=$(echo "${currentRel,,}" | tr _ . )

    # newRel: to lower, use dots
    newRel=$(echo "${newRel,,}" | tr - . )
    newRel=$(echo "${newRel,,}" | tr _ . )

    #support for dev upgrades
    if [ "${packName}" == "jfmc" ] && [[ "${currentVer}" == *[b]* ]]; then
        currentVer=$(echo "${currentVer,,}" | sed 's/b//g' )
    fi

    # newVer: to lower, use dots
    newVer=$(echo "${newVer,,}" | tr - . )
    newVer=$(echo "${newVer,,}" | tr _ . )

    #support for dev upgrades
    if [ "${packName}" == "jfmc" ] && [[ "${newVer}" == *[b]* ]]; then
        newVer=$(echo "${newVer,,}" | sed 's/b//g' )
    fi

    if [ "${currentName}" == "${newName}" ]; then
        verComp "${currentVer}" "${newVer}" 2>/dev/null
        verCompResult=$?
        if [ ${verCompResult} -eq 0 ] || [ ${verCompResult} -eq 1 ]; then
            # compare release numbers
            verComp "${currentRel}" "${newRel}" 2>/dev/null
            relCompResult=$?
            
            if [ ${relCompResult} -eq 0 ] || [ ${relCompResult} -eq 1 ]; then
                log "${packName} [$currentVer] version is already installed"
            elif [ ${relCompResult} -eq 2 ]; then
                log "INFO: ${packName} [$currentVer] ($currentRel) version is installed, going to upgrade to [$newVer] ($newRel) version"
                return 2
            fi

        elif [ ${verCompResult} -eq 2 ]; then
            log "INFO: ${packName} [$currentVer] version is installed, going to upgrade to [$newVer] version"
            return 2
        fi
    else
        # This version is not installed
        return 1
    fi

    return 0
}

# Extract package name by using package file as input
# usage : getPackName "libvpx1_1.3.0-3_amd64.deb"
getPackName() {
    local file="$1"
    if [ ! -f $file ]
    then
        file="packages/$file"
    fi
    if [ ! -z $file ]; then
        if [[ $file == *.deb ]]; then
            echo $(dpkg --info ${file} | grep Package | awk -F ': ' '{print $2}')
        elif [[ $file == *.rpm ]]; then
            echo $(rpm -qip --nosignature ${file} | grep "Name " | awk -F ': ' '{print $2}')
        fi
    else
        echo ""
    fi
}

installPackageName() {
    local packName=$1
    case ${DIST} in
        CentOS|RedHat)
            yum install -y $1 1>&6 2>&1
        ;;
        Debian|Ubuntu)
            apt-get install -y $1 1>&6 2>&1
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
    if [ $? -ne 0 ]; then
      errorExit "Installation of $packName failed"  
    fi
}

# Generic method to install debian package using package name
# usage : installPackage "libvpx1_1.3.0-3_amd64.deb"
# for rpm upgrade :  installPackage "libvpx1_1.3.0-3_amd64.deb" "upgrade"
installPackage() {
    local packFile=$1
    local strictCheck=$2
    local mode=$3
    local upgradeMode=$4
    local rpmOptions

    # run upgrade of rpm if 'upgrade' is passed as the third argument
    [[ ! -z "$mode" ]] && [[ "$mode" == *"upgrade"* ]] && rpmOptions="Uvh" || rpmOptions="ivh"

    if [[ ! -f "$packFile" ]]
    then    
        packFile="packages/$packFile"
    fi
    log "Installing pack file: $packFile" "DEBUG" >&6 2>&1
    local packName=$(getPackName ${packFile})
    log "Installing packName: $packName" "DEBUG" >&6 2>&1

    [ ! -z ${packName} ] || errorExit "Installing ${packFile} failed, could not determine packname using package"

    isPackInstalled "${packName}" "${packFile}" "${strictCheck}"

    if [ $? -eq 0 ]; then
        log "Skipping ${packName} Installation"
    elif [[ $? -eq 2 ]] && [[ ! -z "$upgradeMode" ]] && [[ "$upgradeMode" == *"skip"* ]]; then 
        log "Skipping ${packName} Installation"
    elif [[ $packFile == *.deb ]]; then
        log "Installing as deb" "DEBUG" >&6 2>&1
        dpkg -i ${packFile} >&6 2>&1 || errorExit "Installing ${packName} package failed"
    elif [[ $packFile == *.rpm ]]; then
        log "Installing as rpm" "DEBUG" >&6 2>&1
        rpm -${rpmOptions} --nosignature --replacepkgs ${packFile} >&6 2>&1 || errorExit "Installing ${packName} package failed"
    fi
}

# Accepts one parameter which needs to be a string with space delimited list of package files
# usage : installMultiplePackages "libvpx1_1.3.0-3_amd64.deb libxpm4_1-3a3.5.12-0+deb8u1_amd64.deb"
installMultiplePackages() {
    local fileList=($1)

    for packFile in "${fileList[@]}"
    do
        installPackage "${packFile}"
    done
}

# Attempts to start services
startService() {
    local packName=$1

    log "Starting ${packName}"
    local status_command
    local start_command
    #The order of if and else here is important. A file: elasticsearch.service is added to the folder /usr/lib/systemd/system
    #but systemctl may not exist
    if [ -f "/etc/init.d/${packName}" ] || [ -f "/lib/systemd/system/${packName}.service" ] ; then
        status_command="service $packName status"
        start_command="service $packName start"
    elif [ -f "/usr/lib/systemd/system/${packName}.service" ] || [ -f "/etc/systemd/system/${packName}.service" ]; then
        status_command="systemctl status ${packName}"
        start_command="systemctl start ${packName}"
    fi
    ($status_command || $start_command) >&6 2>&1

    log "Command to check status: $status_command" "DEBUG" >&6 2>&1

    local retry_count=0
    local attempstat=1
    while [ ${retry_count} -lt 10 ] && [ ${attempstat} -gt 0 ]; do
        sleep 2
        $status_command >&6 2>&1
        attempstat=$?
        let retry_count=$retry_count+1
    done
    if [ ${attempstat} -gt 0 ]; then
        errorExit "[$packName] failed to start. This may be temporary. Try manually starting the service using [$start_command] & \
verifying its status using [$status_command]. Once it starts successfully, rerun the installer"
    fi
}

#TODO Validate and Document
# Check require system settings for JFMC start (6GB RAM and 4 CPU cores)
checkPrerequisites() {
    local RECOMMENDED_MIN_RAM=6291456     #JFMC needs more than 6G Total RAM => 6*1024*1024k=6291456
    local RECOMMENDED_MAX_USED_STORAGE=90  #JFMC needs more than 10% available storage
    local RECOMMENDED_MIN_CPU=2           #JFMC needs more than 2 CPU Cores
    
    TOTAL_RAM="$(grep ^MemTotal /proc/meminfo | awk '{print $2}')"
    USED_STORAGE="$(df -h /dev/sda1 | tail -n +2 | tr -s ' ' | tr '%' ' ' | cut -d ' ' -f 5)"
    FREE_CPU="$(grep -c ^processor /proc/cpuinfo)"
    local msg=""

    if [[ ${TOTAL_RAM} -lt ${RECOMMENDED_MIN_RAM} ]]; then
        let "TOTAL_RAM_TO_SHOW = ${TOTAL_RAM} / 1024 / 1024"
        let "RECOMMENDED_MIN_RAM_TO_SHOW = ${RECOMMENDED_MIN_RAM} / 1024 / 1024"
        msg="WARNING: Running with ${TOTAL_RAM_TO_SHOW}GB Total RAM. Recommended value: ${RECOMMENDED_MIN_RAM_TO_SHOW}GB"
        echo -e "\033[33m${msg}\033[0m"
    fi;

    if [[ ${USED_STORAGE} -gt ${RECOMMENDED_MAX_USED_STORAGE} ]]; then
        let "AVAILABLE_STORAGE = 100 - ${USED_STORAGE}"
        msg="WARNING: Running with $AVAILABLE_STORAGE% Free Storage"
        echo -e "\033[33m${msg}\033[0m"
    fi;

    if [ ${FREE_CPU} -lt ${RECOMMENDED_MIN_CPU} ]; then
        msg="WARNING: Running with $FREE_CPU CPU Cores"
        echo -e "\033[33m${msg}\033[0m"
    fi;
}

checkPrerequisitesSoftware() {
    # Validate that PHP and Java are available
    local RECOMMENDED_PHP_VER
    case $DIST in
        CentOS|RedHat)
            RECOMMENDED_PHP_VER="5.4"
        ;;
        Debian|Ubuntu)
            RECOMMENDED_PHP_VER="5.6"
        ;;
    esac
    
    php -v | grep "PHP $RECOMMENDED_PHP_VER" -wq >&6 2>&1
    if [ $? -ne 0 ]; then
      errorExit "Please install version $RECOMMENDED_PHP_VER of PHP before continuing"  
    fi
    local RECOMMENDED_JAVA_VER="1.8"
    
    java -version 2>&1 | grep "$RECOMMENDED_JAVA_VER" >&6 2>&1
    if [ $? -ne 0 ]; then
      errorExit "Please install version $RECOMMENDED_JAVA_VER of Java before continuing"  
    fi

    # Validate that any pre-requisites specified by the 3rd party libraries are present
    local USER_END_INSTALLS=$1
    local unavailableTools=""
    local toolList=($USER_END_INSTALLS)
    for packName in "${toolList[@]}"
    do
       isInstalled "${packName}"
       if [ $? -eq 1 ] ; then
          unavailableTools="${unavailableTools} ${packName}"
       fi
    done
    local command_to_run
    case $DIST in
        CentOS|RedHat)
            command_to_run="yum install -y ${unavailableTools}"
        ;;
        Debian|Ubuntu)
            command_to_run="apt-get install -y ${unavailableTools}"
        ;;
    esac
    if [ ! -z "${unavailableTools}" ]; then
      errorExit "Some dependencies the installer needs are missing. \
Please install them using [${command_to_run}] and then try again. \n\n(NOTE: You may need to tweak the list of sources in some cases)"
    fi
}


# Utility method to check if a value (first paramter) exists in an array (2nd parameter)
# 1st parameter "value to find"
# 2nd parameter "The array to search in. Please pass a string with each value separated by space"
# Example: containsElement "y" "y Y n N"
containsElement () {
  local searchElement=$1
  local searchArray=($2)
  local found=1
  for elementInIndex in "${searchArray[@]}";do
    if [[ $elementInIndex == $searchElement ]]; then
        found=0
    fi
  done
  return $found
}

configureLogOutput() {
    if [[ ! -z $INSTALLATION_LOG_FILE ]]; then
        exec 6>>$INSTALLATION_LOG_FILE
    else
        exec 6>&1
    fi

}

# Utility method to get user's choice
# 1st parameter "what to ask the user"
# 2nd parameter "what choices to accept, separated by spaces"
# 3rd parameter "what is the default choice (to use if the user simply presses Enter)"
# Example 'getUserChoice "Are you feeling lucky? Punk!" "y n Y N" "y"'
getUserChoice(){
    configureLogOutput
    local choice="na"
    local text_to_display=$1
    local choices=$2
    local default_choice=$3
    users_choice=

    until containsElement "$choice" "$choices"; do
        echo "";echo "";
        sleep $read_timeout #This ensures correct placement of the question.
        read -p  "$text_to_display :" choice
        : ${choice:=$default_choice}
    done
    users_choice=$choice
    echo -e "\n$text_to_display: $users_choice" >&6
    sleep $read_timeout #This ensures correct logging
}

# Utility method to get user's input
# 1st parameter "what to ask the user"
# 3rd parameter "what is the default choice (to use if the user simply presses Enter)"
# Example 'getUserInput "Are you feeling lucky? Punk!" "y"'
getUserInput(){
    configureLogOutput
    local choice="na"
    local text_to_display=$1
    local default_choice=$2
    users_choice=
    
    if [ ! -z $default_choice ]; then
        text_to_display="$1 [$default_choice]:"
    else
        text_to_display="$1 :"
    fi

    echo "";echo "";
    sleep $read_timeout #This ensures correct placement of the question.
    read -p "$text_to_display" choice
    if [ ! -z $default_choice ]; then
        : ${choice:=$default_choice}
    fi
    users_choice=$choice
    echo -e "\n$text_to_display: $users_choice" >&6
    sleep $read_timeout #This ensures correct logging
}


# Utility method to remove environment variables
# 1st parameter "the key to remove"
removeFromEnvFile(){
    local key_to_remove=$1
    #Delete the original entry.
    [[ -f "${JFMC_MASTER_ENV}" ]] && sed -i "/export $key_to_remove/d" "${JFMC_MASTER_ENV}"
    [[ -f "${JFMC_MODIFIED_ENV}" ]] && sed -i "/export $key_to_remove/d" "${JFMC_MODIFIED_ENV}"
}

# Utility method to add environment variables to setEnv.sh
# 1st parameter "the key to add"
# 2nd parameter "add env to beginning or end of file"

addToEnvFile(){
    if [[ -z "$1" || "$1" == "" ]]; then
        return
    fi

    local key_to_add=$1
    # Get the value associated with this variable (indirect reference)

    local value_to_add=${!1}

    local string_add_location=${2:-end}
    local env_path=

    if [[ -f "${JFMC_MASTER_ENV}" ]]; then
        env_path="${JFMC_MASTER_ENV}"
        if [[ ! -z "$value_to_add" ]]; then
            # Delete the original entry. NOTE: This will also ensure that if a value is not available, it is removed from the file
            sed -i "/export $key_to_add/d" "$env_path"

            # Append string to 2nd line or end of file based on location
            [[ "$string_add_location" == "end" ]] && echo "export $key_to_add=\"$value_to_add\"" >> "$env_path" || sed -i "2s/^/export $key_to_add=\"$value_to_add\"\n/" "$env_path"
        fi
    fi
    if [[ -f "${JFMC_MODIFIED_ENV}" ]]; then
        # Set env path to current script only if main env file is not created
        # Retain user modified env variables if the same script is executed multiple times
        env_path="$JFMC_MODIFIED_ENV"

        if [[ ! -z "$value_to_add" && -f "$env_path" ]]; then
            sed -i "/export $key_to_add/d" "$env_path"
            echo "export $key_to_add=\"$value_to_add\"" >> "$env_path"
        fi
    fi
}


addToDependentServices() {
    service_to_add=$1
    if [[ $string != *"$service_to_add"* ]]; then
        DEPENDENT_SERVICES="$DEPENDENT_SERVICES $service_to_add"
    fi
}

# ------------------------------------------------------------------------------
# Install dependent packages
# ------------------------------------------------------------------------------

# install curl and its dependencies
installCURL() {
    title "Installing curl"
    log "Installing/Verifying curl (this may take several minutes)..."
    local packFile
    case ${DIST} in
        CentOS|RedHat)
            packFile="curl-7.29.0-42.el7.x86_64.rpm"
            
        ;;
        Debian)
            packFile="curl_7.38.0-4+deb8u7_amd64.deb"
        ;;
        Ubuntu)
            packFile="curl.deb"
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
    # skip upgrade if its already installed
    installPackage "${packFile}" "no" "install" "skip"
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installCURL"
THIRD_PARTY_DEPENDENCIES_DEBIAN="$THIRD_PARTY_DEPENDENCIES_DEBIAN libcurl3"
THIRD_PARTY_DEPENDENCIES_UBUNTU="$THIRD_PARTY_DEPENDENCIES_UBUNTU libcurl3"

jqPackage="jq-linux64"

# installs jq
# expects one variable to be set with appropriate value,
#   jqPackage
installJQ() {
    title "Installing jq"
    log "Installing/Verifying jq ..."
    case ${DIST} in
        CentOS|RedHat|Debian|Ubuntu)
            # check if jq is installed
            if [ ! -f /usr/bin/jq ]; then
                cp packages/${jqPackage} /usr/bin/jq && \
                chmod +x /usr/bin/jq || errorExit "Could not install jq"
            else
                log "Skipping installation of jq"
            fi
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installJQ"

# installs unzip
# expects one variable to be set with appropriate value,
#   unzipPackage
installUnzip() {
    title "Installing unzip"
    local unzipPackage
    log "Installing/Verifying unzip ..."
    case ${DIST} in
        CentOS|RedHat)
            unzipPackage="unzip.rpm"
        ;;
        Debian|Ubuntu)
            unzipPackage="unzip.deb"
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
    # skip upgrade if its already installed
    installPackage "${unzipPackage}" "no" "install" "skip"
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installUnzip"

# ------------------------------------------------------------------------------
# Configure Postgres
# ------------------------------------------------------------------------------

getPostgresDefaults

checkPostgresNotInJFMC() {
    local folder=$1
    VALID_POSTGRES_DATA_FOLDER="no"
    #prevent creating $POSTGRES_LABEL data inside Mission Control data because of users permissions
    echo ${folder} | grep -E "^${JFMC_DATA}" 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        log "WARNING: $POSTGRES_LABEL folder cannot be inside Mission Control data folder"
    else
        VALID_POSTGRES_DATA_FOLDER="yes"
    fi
}

getPostgresDetails() {
    getUserInput "Please enter the path where $POSTGRES_LABEL executable (psql) is available" "$POSTGRES_PATH"
    export POSTGRES_PATH=$users_choice
    
    getUserInput "Please enter the ID of the root user" "$POSTGRES_ROOT_USER_ID"
    export POSTGRES_ROOT_USER_ID=$users_choice

    getUserInput "Please enter the password of the root user" "$POSTGRES_ROOT_USER_PWD"
    export POSTGRES_ROOT_USER_PWD=$users_choice
}

createPostgresData() {
        
        if [ -f "${POSTGRES_USERS_CREATED_FILE}" ];then
            return 0
        fi

        if [[ -z $POSTGRES_PATH || -z $POSTGRES_ROOT_USER_ID || -z $POSTGRES_ROOT_USER_PWD ]]; then
            getPostgresDetails
        fi
        
        export POSTGRES_PATH="$POSTGRES_PATH"
        export POSTGRES_ROOT_USER_ID="$POSTGRES_ROOT_USER_ID"
        export POSTGRES_ROOT_USER_PWD="$POSTGRES_ROOT_USER_PWD"
        export POSTGRES_OMNI_DB="$POSTGRES_OMNI_DB"
        export POSTGRES_USER="$POSTGRES_USER"
        export POSTGRES_PWD="$POSTGRES_PWD"

        bash ${JFMC_DATA}/seed_data/postgres/createPostgresData.sh

        if [[ $? -ne 0 ]]; then
            if [[ $TYPE_OF_INSTALLATION == "standard" ]];then
                errorExit "Failed to seed $POSTGRES_LABEL"
            fi
            warn "Failed to  seed $POSTGRES_LABEL. Would you like to review your inputs and try again?\
(Choose 'Y' to retry, 'N' to abort or 'S' to skip this step)"
            
            getUserChoice "Retry operation? [Y/n/s]" "y n Y N S s" "y"
            if [[ $users_choice =~ n|N ]]; then
                errorExit "Failed to seed $POSTGRES_LABEL"
            elif [[ $users_choice =~ s|S ]]; then
                SEED_POSTGRES="n";
                warn "Files which can be used to seed $POSTGRES_LABEL are available at [${JFMC_DATA}/seed_data] \
Please seed $POSTGRES_LABEL before starting Mission-Control" #Don't add a tab to this line
                touch $POSTGRES_USERS_CREATED_FILE
                echo "User chose to seed manually" >> $POSTGRES_USERS_CREATED_FILE
            else
                getPostgresDetails
                createPostgresData
            fi
        else
            touch $POSTGRES_USERS_CREATED_FILE
        fi
}

POSTGRES_ALREADY_INSTALLED="no"
isPostgresInstalled() {
    service "$POSTGRES_SERVICE" status 2>&1 | grep -E 'No such file or directory|could not be found|unrecognized service' -wq
    local POSTGRES_FOUND=$(echo $?)
    if [[ ${POSTGRES_FOUND} != 0 ]]; then
        POSTGRES_ALREADY_INSTALLED="yes"
    fi
}

#This code is necessary since postgres assumes a different user (and the jfrog folder may be owned by jfrogmc)
setPostgresFolder() {
    if [[ -d $POSTGRES_HOME_DEFAULT || $TYPE_OF_INSTALLATION == "standard"  ]]; then
        users_choice=${POSTGRES_HOME_DEFAULT}
    else
        log "$POSTGRES_LABEL home must be set on Mission Control first installation"
        log "Type desired POSTGRES_HOME location or press Enter to accept the default"
        
        getUserInput "Enter $POSTGRES_LABEL home folder" "${POSTGRES_HOME_DEFAULT}"
    fi
    if [ "${users_choice}" != "${POSTGRES_HOME_DEFAULT}" ]; then
        checkPostgresNotInJFMC ${users_choice}
        until [ "${VALID_POSTGRES_DATA_FOLDER}" == "yes" ]; do
            getUserInput "Enter $POSTGRES_LABEL home folder" "${POSTGRES_HOME_DEFAULT}"
            checkPostgresNotInJFMC ${users_choice}
        done
    fi
    POSTGRES_HOME=$users_choice
    POSTGRES_DATA=${POSTGRES_HOME}/data
}

installNewPostgres() {
    getPostgresDefaults

    log "Checking if $POSTGRES_LABEL already exists" >&6 2>&1
    isPostgresInstalled
    if [[ $POSTGRES_ALREADY_INSTALLED == "yes" ]]; then
        log "$POSTGRES_LABEL is already installed. Skipping installation/upgrade"
    else
        setPostgresFolder
        log "Creating $POSTGRES_LABEL data folder on $POSTGRES_DATA"
        mkdir -p ${POSTGRES_DATA} || errorExit "Creating ${POSTGRES_DATA} folder failed"

        cd ${INSTALLER_DIR} || errorExit "Entering ${INSTALLER_DIR} folder failed"
        
        log "Installing/Verifying $POSTGRES_LABEL (this may take several minutes)..."
        chmod +x ./packages/postgresql-*.run
        LC_ALL="C" ./packages/postgresql-*.run --unattendedmodeui none --mode unattended --datadir ${POSTGRES_DATA} || errorExit "Installing $POSTGRES_LABEL failed"
        chown -R postgres:postgres ${POSTGRES_HOME} || errorExit "Setting owner postgres on $POSTGRES_DATA failed"
    
        sleep 10
        # Stop postgress if it is already running under /var/opt/postgres/data
        [ -f "${POSTGRES_DATA}/postmaster.pid" ] && cat "${POSTGRES_DATA}/postmaster.pid" | head -1 | xargs kill -9
        startService "$POSTGRES_SERVICE" 
    fi
    sleep 5
    createPostgresData
}


externalizePostgres() {
    local INSTALLATION_MSG="Install/Upgrade $POSTGRES_LABEL as part of this installation? \n(Choose n if you want to externalize $POSTGRES_LABEL)"
    log "$INSTALLATION_MSG"
    getUserChoice "Install $POSTGRES_LABEL? [Y/n]" "y n Y N" "y"
    INSTALL_POSTGRES=${users_choice}

    if [[ $INSTALL_POSTGRES =~ n|N ]]; then
        getUserInput "Please enter the $POSTGRES_LABEL Host" "$POSTGRESDB_HOST"
        POSTGRESDB_HOST=$users_choice
        
        #Ask the port to connect to
        getUserInput "Please enter the $POSTGRES_LABEL port" "$JFMC_POSTGRES_PORT"
        JFMC_POSTGRES_PORT=$users_choice

        QUARTZ_DB_URL="$POSTGRESDB_HOST:$JFMC_POSTGRES_PORT"

        if [ ! -f "${POSTGRES_USERS_CREATED_FILE}" ];then

            log "If $POSTGRES_LABEL is installed as a service on this machine, the installer can attempt to seed the databases and users.\n\
    (Choose 'Y' only if $POSTGRES_LABEL is installed locally AND you have the credentials necessary to setup $POSTGRES_LABEL)" #Don't add a tab to this line

            getUserChoice "Attempt to seed $POSTGRES_LABEL? [y/N]" "y n Y N" "n"
            SEED_POSTGRES=$users_choice
            if [[ $SEED_POSTGRES =~ y|Y ]]; then
                log "You will now be prompted to enter the location of the $POSTGRES_LABEL executable and credentials of a user who can create databases/other users"
                getPostgresDetails
                createPostgresData
            else
                warn "Files which can be used to seed $POSTGRES_LABEL are available at [${JFMC_DATA}/seed_data] \
    Please seed $POSTGRES_LABEL before starting Mission-Control" #Don't add a tab to this line
            fi
        fi


    else
        installNewPostgres
    fi
}

installPostgres() {
    title "$POSTGRES_LABEL Installation"
    mkdir -p ${JFMC_DATA}/seed_data/postgres

    POSTGRES_USERS_CREATED_FILE="$JFMC_INSTALL_LOGS/postgres_data.created"
    
    #Copying files necessary for externalization to the seed_data folder
    cp ${SEED_DATA}/createPostgresData.sh ${JFMC_DATA}/seed_data/postgres
    cp ${SEED_DATA}/quartz_postgres.sql ${JFMC_DATA}/seed_data/postgres

    : ${INSTALL_POSTGRES:="Y"}

    if [[ $TYPE_OF_INSTALLATION == "standard" ]];then
        if [[ $IS_UPGRADE != true || $INSTALL_POSTGRES =~ y|Y ]]; then
            installNewPostgres
        else
            log "skipping externalized $POSTGRES_LABEL instance"
        fi
    else
        externalizePostgres
    fi

    updatePostGres #Immediately put the current values into the file
}

updatePostGres() {
    addToEnvFile "INSTALL_POSTGRES"
    if [[ $INSTALL_POSTGRES =~ y|Y ]]; then
        removeFromEnvFile "SEED_POSTGRES"
        log "Adding $POSTGRES_LABEL as dependency"
        addToDependentServices "$POSTGRES_SERVICE"
        addToEnvFile "POSTGRES_HOME"
    else
        removeFromEnvFile "POSTGRES_HOME"
        addToEnvFile "SEED_POSTGRES"
    fi
    addToEnvFile "QUARTZ_DB_URL"

    if [[ ! -z "$POSTGRES_OMNI_DB" && "$POSTGRES_OMNI_DB" != "" ]]; then
        export POSTGRES_DB="$POSTGRES_OMNI_DB"
        addToEnvFile "POSTGRES_DB"
    fi
    
    addToEnvFile "POSTGRES_USER"
    addToEnvFile "POSTGRES_PWD"
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installPostgres"
POST_INSTALL_TASKS="$POST_INSTALL_TASKS updatePostGres"
OPTIONAL_PORT_LIST="$OPTIONAL_PORT_LIST JFMC_POSTGRES_PORT"

# ------------------------------------------------------------------------------
# Configure MongoDB
# ------------------------------------------------------------------------------

CENTOS_MONGODB_SERVER6="mongodb-org-server-3.2.6-1.el6.x86_64"
CENTOS_MONGODB_SHELL6="mongodb-org-shell-3.2.6-1.el6.x86_64"
CENTOS_MONGODB_SERVER7="mongodb-org-server-3.2.6-1.el7.x86_64"
CENTOS_MONGODB_SHELL7="mongodb-org-shell-3.2.6-1.el7.x86_64"
DEBIAN_MONGODB_SERVER="mongodb-org-server-3.2.6_amd64"
DEBIAN_MONGODB_SHELL="mongodb-org-shell-3.2.6_amd64"

#These will eventually end up (after the installation) in setEnv

getMongoDefaults

MONGO_SERVICE="mongod"

createMongoData() {
    if [ -f "${MONGO_USERS_CREATED_FILE}" ];then
        return
    fi
    export MONGO_PATH=${SEED_DATA}
    export MONGODB_PORT=$JFMC_MONGO_PORT #whether this field is available or not lets the script createMongoUsers.sh know if it has been invoked separately
    bash ${SEED_DATA}/createMongoUsers.sh
    if [[ $? -ne 0 ]]; then
        if [[ $TYPE_OF_INSTALLATION == "standard" ]];then
          errorExit "$MONGO_LABEL seeding failed due to errors"
        fi
        warn "Failed to  seed $MONGO_LABEL. Would you like to review your inputs and try again?\
(Choose 'Y' to retry, 'N' to abort or 'S' to skip this step)"
        
        getUserChoice "Retry operation? [Y/n/s]" "y n Y N S s" "y"
        
        if [[ $users_choice =~ n|N ]]; then
            errorExit "Failed to seed $MONGO_LABEL"
        elif [[ $users_choice =~ s|S ]]; then
            SEED_MONGO="n"
            warn "Files which can be used to seed $MONGO_LABEL are available at [${JFMC_DATA}/seed_data] \
Please seed $MONGO_LABEL before starting Mission-Control" #Don't add a tab to this line
            touch $MONGO_USERS_CREATED_FILE
            echo "User chose to seed manually" >> $MONGO_USERS_CREATED_FILE
        else
            getMongoDetails
            createMongoData
        fi
    else
        touch $MONGO_USERS_CREATED_FILE
    fi
}

installNewMongoDB() {
    getMongoDefaults
    
    log "Installing/Verifying $MONGO_LABEL (this may take several minutes)..."
    local isInstalled="no"
    case ${DIST} in
        CentOS|RedHat)
            eval mongodb_org_server="\${CENTOS_MONGODB_SERVER${DIST_VER}}.rpm"
            eval mongodb_org_shell="\${CENTOS_MONGODB_SHELL${DIST_VER}}.rpm"
            installMultiplePackages "$mongodb_org_server $mongodb_org_shell"
        ;;
        Debian|Ubuntu)
            installMultiplePackages "${DEBIAN_MONGODB_SERVER}.deb ${DEBIAN_MONGODB_SHELL}.deb"
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
    isInstalled="yes"
    if [ "${isInstalled}" == "yes" ]; then
       startService $MONGO_SERVICE
       sleep 10
       export MONGODB_PORT="$JFMC_MONGO_PORT"
       createMongoData
    fi
}

MONGO_ALREADY_INSTALLED="no"
isMongoInstalled() {
    service "$MONGO_SERVICE" status 2>&1 | grep -E 'No such file or directory|could not be found|unrecognized service' -wq
    local MONGO_FOUND=$(echo $?)
    if [[ ${MONGO_FOUND} != 0 ]]; then
        MONGO_ALREADY_INSTALLED="yes"
    fi
}

externalizeMongo() {
        export LOCAL_MONGO="yes"
        createMongoData
}

installMongoDB() {
    title "$MONGO_LABEL Installation"

    : ${INSTALL_MONGO:="Y"}
    MONGO_USERS_CREATED_FILE="$JFMC_INSTALL_LOGS/mongo_users.created"

    mkdir -p ${JFMC_DATA}/seed_data/mongodb
    cp ${SEED_DATA}/createMongoUsers.sh ${JFMC_DATA}/seed_data/mongodb
    cp ${SEED_DATA}/createMongoUsers.js ${JFMC_DATA}/seed_data/mongodb

    isMongoInstalled

    if [[ $EXTERNALIZE_MONGO != "true" ]];then
        if [[ $IS_UPGRADE != true || $INSTALL_MONGO =~ y|Y ]]; then
            installNewMongoDB
        else
            log "skipping externalized $MONGO_LABEL instance"
        fi
    else
        externalizeMongo  
    fi

    updateMongoParams
}

updateMongoParams() {
    addToEnvFile "INSTALL_MONGO"
    addToEnvFile "JFMC_MONGO_PORT"
    addToEnvFile "SPRING_DATA_MONGODB_PORT"
    addToEnvFile "SPRING_DATA_MONGODB_HOST"
    addToEnvFile "MONGO_URL"
    addToEnvFile "MONGODB_USERNAME"
    addToEnvFile "MONGODB_PASSWORD"

    if [[ $INSTALL_MONGO =~ y|Y ]]; then
        removeFromEnvFile "SEED_MONGO"
        log "Adding $MONGO_LABEL as dependency"
        addToDependentServices "$MONGO_SERVICE"
    else
        addToEnvFile "SEED_MONGO"
    fi
}

POST_INSTALL_TASKS="$POST_INSTALL_TASKS updateMongoParams"
THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installMongoDB"
OPTIONAL_PORT_LIST="$OPTIONAL_PORT_LIST JFMC_MONGO_PORT"

# ------------------------------------------------------------------------------
# Configure elastic search
# ------------------------------------------------------------------------------


DEBIAN_ELASTICSEARCH_PKG="elasticsearch_5.6.2_all"
CENTOS_ELASTICSEARCH_PKG="elasticsearch-5.6.2"

#These will eventually end up (after the installation) in setEnv

getElasticSearchDefaults

ELASTIC_SEARCH_SERVICE="elasticsearch"

createElasticSearchIndices() {
    if [ -f "${ELASTICSEARCH_USERS_CREATED_FILE}" ];then
        return
    fi
    export ELASTIC_SEARCH_URL="$ELASTIC_SEARCH_URL"
    if [ ! -z $ELASTIC_SEARCH_USERNAME ]; then
        export ELASTIC_SEARCH_USERNAME="$ELASTIC_SEARCH_USERNAME"
        export ELASTIC_SEARCH_PASSWORD="$ELASTIC_SEARCH_PASSWORD"
    fi
    chmod +x ${SEED_DATA}/createIndices.sh
    bash ${SEED_DATA}/createIndices.sh
    if [[ $? -ne 0 ]]; then
        if [[ $TYPE_OF_INSTALLATION == "standard" ]];then
            errorExit "Failed to seed $ELASTIC_SEARCH_LABEL"
        fi
        warn "Failed to  seed $ELASTIC_SEARCH_LABEL. Would you like to review your inputs and try again?\
(Choose 'Y' to retry, 'N' to abort or 'S' to skip this step)"

        getUserChoice "Retry operation? [Y/n/s]" "y n Y N S s" "y"
            
        if [[ $users_choice =~ n|N ]]; then
            errorExit "Failed to seed $ELASTIC_SEARCH_LABEL"
        elif [[ $users_choice =~ s|S ]]; then
            SEED_ELASTIC_SEARCH="n"
            touch $ELASTICSEARCH_USERS_CREATED_FILE
            echo "User chose to seed manually" >> $ELASTICSEARCH_USERS_CREATED_FILE
            warn "Files which can be used to seed $ELASTIC_SEARCH_LABEL are available at [${JFMC_DATA}/seed_data] \
Please seed $ELASTIC_SEARCH_LABEL before starting Mission-Control" #Don't add a tab to this line
        else
            getElasticSearchDetails
            createElasticSearchIndices
        fi
    else
        touch $ELASTICSEARCH_USERS_CREATED_FILE
    fi
}

setRecommendedConfiguration() {
    log "Setting recommended configuration for $ELASTIC_SEARCH_LABEL"
    #Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-system-settings.html#limits.conf
    ulimit -n 65536
    #Reference: https://www.elastic.co/guide/en/elasticsearch/reference/5.0/vm-max-map-count.html
    sysctl -w vm.max_map_count=262144

    addLine "elasticsearch - nofile 65536" "/etc/security/limits.conf"
    addLine "cluster.name: es-cluster" "/etc/elasticsearch/elasticsearch.yml"

    # This parameter only needs to be set when testing within docker    
    if [ "$JFMC_DOCKER_MODE" == "yes" ]
    then
        addLine "network.host: 0.0.0.0" "/etc/elasticsearch/elasticsearch.yml"
    fi

    # Reference https://www.elastic.co/guide/en/elasticsearch/reference/current/setup-configuration-memory.html#mlockall
    #TMP causes crash echo "bootstrap.memory_lock: true" >> /etc/elasticsearch/elasticsearch.yml

    #JVM min and max memory

    local TOTAL_RAM="$(grep ^MemTotal /proc/meminfo | awk '{print $2}')"
    let "TOTAL_RAM_TO_SHOW = ${TOTAL_RAM} / 1024 / 1024"
    local MEM_UNIT
    local MEM_VALUE
    
    if [[ ${TOTAL_RAM_TO_SHOW} -lt 1 ]]; then
        MEM_UNIT="m"
        let MEM_VALUE=512
    else
        MEM_UNIT="g"
        let MEM_VALUE="$TOTAL_RAM_TO_SHOW / 2"
    fi

    log "Setting memory configuration as $MEM_VALUE$MEM_UNIT"
    sed -i "s#-Xms2g#-Xms$MEM_VALUE$MEM_UNIT#g" /etc/elasticsearch/jvm.options
    sed -i "s#-Xmx2g#-Xmx$MEM_VALUE$MEM_UNIT#g" /etc/elasticsearch/jvm.options

    #Reference https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-system-settings.html#systemd
    mkdir -p /etc/systemd/system/elasticsearch.service.d
    local conf_file="/etc/systemd/system/elasticsearch.service.d/elasticsearch.conf"
    if [ ! -f "${conf_file}" ]; then
        touch /etc/systemd/system/elasticsearch.service.d/elasticsearch.conf
    fi

    addLine "[Service]" $conf_file
    addLine "LimitMEMLOCK=infinity" $conf_file
}

installNewElasticSearch() {
    getElasticSearchDefaults
    log "Installing/Verifying $ELASTIC_SEARCH_LABEL (this may take several minutes)..."
    local isInstalled="no"
    local packFile
    case ${DIST} in
        CentOS|RedHat)
            installPackage "${CENTOS_ELASTICSEARCH_PKG}.rpm"
        ;;
        Debian|Ubuntu)
            installPackage "${DEBIAN_ELASTICSEARCH_PKG}.deb"
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac

    isInstalled="yes"

    if [ "${isInstalled}" == "yes" ]; then
        #TODO Discuss. Should this happen even if elasticsearch is already installed
        setRecommendedConfiguration
        startService "$ELASTIC_SEARCH_SERVICE"
    fi
    sleep 10
    createElasticSearchIndices
}

getElasticSearchDetails() {

    getUserInput "Please enter the $ELASTIC_SEARCH_LABEL host url?" "$ELASTIC_ADDRESS"
    ELASTIC_ADDRESS=$users_choice

    #Ask the user the Elastic search Port
    getUserInput "Please enter the $ELASTIC_SEARCH_LABEL Port" "$JFMC_ELASTIC_PORT"
    JFMC_ELASTIC_PORT=$users_choice

    getUserInput "Please enter the $ELASTIC_SEARCH_LABEL cluster name" "$ELASTIC_CLUSTER_NAME"
    ELASTIC_CLUSTER_NAME=$users_choice

    #Ask the user the communications url
    getUserInput "Please enter the $ELASTIC_SEARCH_LABEL communications url" "$ELASTIC_COMMUNICATION_NODE_URL"
    ELASTIC_COMMUNICATION_NODE_URL=$users_choice
    
    #Ask the user the URL to connect to
    ELASTIC_SEARCH_URL="$ELASTIC_ADDRESS:$JFMC_ELASTIC_PORT"
    
    getUserChoice "Does this $ELASTIC_SEARCH_LABEL instance need credentials to access? (If you choose Y you will be prompted to enter them) [Y/n]" "y n Y N" "y"
    if [[ $users_choice == "y" || $users_choice == "Y" ]]; then

        #Ask the user the ID
        getUserInput "Please enter the User ID" 
        ELASTIC_SEARCH_USERNAME=$users_choice

        #Ask the user the password
        getUserInput "Please enter the Password"
        ELASTIC_SEARCH_PASSWORD=$users_choice
    else
        ELASTIC_SEARCH_USERNAME=
        ELASTIC_SEARCH_PASSWORD=
    fi
}

externalizeElasticSearch() {
    local INSTALLATION_MSG="Install/Upgrade $ELASTIC_SEARCH_LABEL as part of this installation? \n(Choose n if want to externalize $ELASTIC_SEARCH_LABEL)"
    log "$INSTALLATION_MSG"

    getUserChoice "Install $ELASTIC_SEARCH_LABEL? [Y/n]" "y n Y N" "y" #Don't add a tab to this line
        
    INSTALL_ELASTIC_SEARCH=${users_choice}
    if [[ $INSTALL_ELASTIC_SEARCH =~ n|N ]]; then
        getElasticSearchDetails
        
        if [ ! -f "${ELASTICSEARCH_USERS_CREATED_FILE}" ];then
            log "The installer can attempt to seed $ELASTIC_SEARCH_LABEL with the necessary databases and users. \n\
    (Choose 'N' if you prefer to do so manually. You will need to create the databases and users before starting Mission control)" #Don't add a tab to this line

            getUserChoice "Attempt to seed $ELASTIC_SEARCH_LABEL? [y/N]" "y n Y N" "n"
            SEED_ELASTIC_SEARCH=$users_choice
            if [[ $SEED_ELASTIC_SEARCH =~ y|Y ]]; then
                createElasticSearchIndices
            else
                warn "Files which can be used to seed $ELASTIC_SEARCH_LABEL are available at [${JFMC_DATA}/seed_data] \
    Please seed $ELASTIC_SEARCH_LABEL before starting Mission-Control" #Don't add a tab to this line
            fi
        fi
    else
        installNewElasticSearch
    fi
}

installElasticSearch() {
    title "$ELASTIC_SEARCH_LABEL Installation"

    : ${INSTALL_ELASTIC_SEARCH:="Y"}
    ELASTICSEARCH_USERS_CREATED_FILE="${JFMC_INSTALL_LOGS}/elastic_indices.created"

    mkdir -p ${JFMC_DATA}/seed_data/elasticsearch
    cp ${SEED_DATA}/createIndices.sh ${JFMC_DATA}/seed_data/elasticsearch

    if [[ $TYPE_OF_INSTALLATION == "standard" ]];then
        if [[ $IS_UPGRADE != true || $INSTALL_ELASTIC_SEARCH =~ y|Y ]]; then
            installNewElasticSearch
        else
            log "skipping externalized $ELASTIC_SEARCH_LABEL instance"
        fi
    else
        externalizeElasticSearch  
    fi

    updateElasticSearch
}

updateElasticSearch() {
    addToEnvFile "INSTALL_ELASTIC_SEARCH"
    addToEnvFile "ELASTIC_SEARCH_URL"
    addToEnvFile "ELASTIC_CLUSTER_NAME"
    addToEnvFile "ELASTIC_COMMUNICATION_NODE_URL"
    addToEnvFile "ELASTIC_SEARCH_USERNAME"
    addToEnvFile "ELASTIC_SEARCH_PASSWORD"
    if [[ $INSTALL_ELASTIC_SEARCH =~ y|Y ]]; then
        removeFromEnvFile "SEED_ELASTIC_SEARCH"
        log "Adding $ELASTIC_SEARCH_LABEL as dependency"
        addToDependentServices "$ELASTIC_SEARCH_SERVICE"
    else
        addToEnvFile "SEED_ELASTIC_SEARCH"
    fi
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installElasticSearch"
POST_INSTALL_TASKS="$POST_INSTALL_TASKS updateElasticSearch"
OPTIONAL_PORT_LIST="$OPTIONAL_PORT_LIST JFMC_ELASTIC_PORT"

# ------------------------------------------------------------------------------
# Configure nginx
# ------------------------------------------------------------------------------

# installs nginx and its dependencies
# expects two variables to be set with appropriate values,
#   nginxPackFile
#   nginxDependencies
installNGinx() {
    local nginxPackFile
    local nginxDependencies
    local isNginxFullInstalled
    local isNginxLightInstalled

    export JFI_CORE_USER_REPLACE="s#@JFMC_USER#$JFMC_USER#g"
    # Externalize jfi-core port
    export JFI_CORE_PORT_REPLACE="s#@JFI_CORE_PORT#$JFMC_CORE_PORT#g"
    export JFI_CORE_INSTALL_REPLACE="s#@JFI_CORE_INSTALL_LOCATION#$JFMC_HOME/bin/php#g"
    export JFMC_LOG_REPLACE="s#@JFMC_LOGS#$JFMC_LOGS#g"
    export JFI_SSL_CORE_PORT_REPLACE="s#@JFI_SSL_CORE_PORT#$JFMC_SSL_CORE_PORT#g"
    export JFI_CORE_SSL_CERTS_LOC_REPLACE="s#@JFI_CORE_SSL_CERTS_LOC#${JFMC_DATA}/insight/etc/security#g"
 
    title "Installing NGINX"
    log "Installing/Verifying NGINX (this may take several minutes)..."
    case ${DIST} in
        CentOS|RedHat)
            nginxPackFile="nginx.rpm"
            installPackage "${nginxPackFile}"
            configureNginx
        ;;
        Debian|Ubuntu)

            nginxPackFile="nginx-light.deb"
            nginxDependencies="nginx-common.deb"
            
            # stop apache if its running 
            service apache2 stop >&6 2>&1;

            isNginxFullInstalled=$(isInstalled nginx-full; echo $?)
            isNginxLightInstalled=$(isInstalled nginx-light; echo $?)

            # do not install nginx light if full or light is installed
            if [[ $isNginxFullInstalled -eq 1 && $isNginxLightInstalled -eq 1 ]]; then
                installPackage "${nginxDependencies}" "no" "install" "skip"
                installPackage "${nginxPackFile}" "no" "install" "skip" && isInstalled_nginx="true"
            fi

            # Stop nginx service if its running
            service nginx stop >&6 2>&1;
            configureNginx
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
}

configureNginx() {
    log "Configuring NGINX"

    # Copy configuration files
    cp config/nginx.conf /etc/nginx/nginx.conf && \
    rm -f /etc/nginx/conf.d/default.conf && \
    cp config/fastcgi_params /etc/nginx/fastcgi_params && \
    cp config/location.conf /etc/nginx/location.conf || errorExit "Could not replace nginx config files"

    # Replace listening port, user and home of JFI core
    sed -i "$JFI_CORE_PORT_REPLACE" /etc/nginx/nginx.conf || errorExit "Could not replace core port in nginx config"
    sed -i "$JFMC_LOG_REPLACE" /etc/nginx/nginx.conf || errorExit "Could not replace core log in ngix config"
    sed -i "$JFI_CORE_USER_REPLACE" /etc/nginx/nginx.conf || errorExit "Could not replace core user in nginx config"
    sed -i "$JFI_CORE_INSTALL_REPLACE" /etc/nginx/location.conf || errorExit "Could not replace core install location in nginx config"

    sed -i "$JFI_SSL_CORE_PORT_REPLACE" /etc/nginx/nginx.conf || errorExit "Could not replace ssl core port in nginx config"
    sed -i "$JFI_CORE_SSL_CERTS_LOC_REPLACE" /etc/nginx/nginx.conf || errorExit "Could not replace ssl core certs location in nginx config"
}

THIRD_PARTY_DEPENDENCIES_CENTOS="$THIRD_PARTY_DEPENDENCIES_CENTOS openssl"
THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installNGinx"

# ------------------------------------------------------------------------------
# Configure php-fpm
# ------------------------------------------------------------------------------

installPhpFpm() {
    export JFI_HOME_CORE="${JFMC_DATA}/jfi-core"
    export JFI_HOME_CORE_REPLACE="s#@JFI_HOME_CORE#$JFI_HOME_CORE#g"

    local packName

    title "Configuring php-fpm"
    log "Configuring php-fpm (this may take several minutes)..."
    case ${DIST} in
        CentOS|RedHat)
            php_ini="/etc/php.ini"
            fpm_conf="/etc/php-fpm.d/www.conf"
        ;;
        Debian|Ubuntu)
            packName="php5-fpm"
            php_directory="/etc/php5"

            if [ ${DIST} == "Ubuntu" ]
            then
                packName="php5.6-fpm"
                php_directory="/etc/php/5.6"

            fi

            # Stop fpm service if its running
            service $packName stop >&6;
            # disable autorestart of php-fpm
            update-rc.d $packName disable >&6 &>/dev/null;
            # if pid parent path is not available, service php5.6-fpm restart fails
            # we are using `service $package restart` on jfmc.start
            createFpmPidPath "$php_directory/fpm/php-fpm.conf"
            
            php_ini="$php_directory/fpm/php.ini"
            fpm_conf="$php_directory/fpm/pool.d/www.conf"
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
    configurePhpFpm
}

# create parent path of fpm pid location 
createFpmPidPath() {
    local CONFFILE=$1
    local PID_PATH=""

    #get pid file path from conf
    local CONF_PIDFILE=$(sed -n 's/^pid[ =]*//p' "${CONFFILE}") && \
    [ ! -z "${CONF_PIDFILE}" ] && [ "${CONF_PIDFILE}" != "" ] && PID_PATH=$(dirname "${CONF_PIDFILE}")

    [ ! -z "${PID_PATH}" ] && [ "${PID_PATH}" != "" ] && mkdir -p "${PID_PATH}" &>/dev/null;
}

configurePhpFpm() {
    log "Configuring php fpm"
    local stringFound
    local targetString
    # Copy configuration files
    cp config/php-fpm-www.conf $fpm_conf || errorExit "Could not replace php fpm config files"

    # Check if phar readonly and expose php install info is already available
    targetString="phar.readonly = Off"
    stringFound=$(isStringFound "$php_ini" "$targetString")
    [[ $stringFound == *"no"* ]] && echo "$targetString" >> $php_ini

    targetString="expose_php=Off"
    stringFound=$(isStringFound "$php_ini" "$targetString")
    [[ $stringFound == *"no"* ]] && echo "$targetString" >> $php_ini

    sed -i "s/^\(max_execution_time =\).*/\1 600/" $php_ini && \
    sed -i "s/^\(max_input_time =\).*/\1 600/" $php_ini && \
    sed -i.bak s@memory_limit\ =\ .*@memory_limit\ =\ 1024M@g $php_ini || errorExit "Could not configure php fpm"

    # Replace user of JFI core
    sed -i "$JFMC_LOG_REPLACE" $fpm_conf || errorExit "Could not replace core log in fpm config"
    sed -i "$JFI_CORE_USER_REPLACE" $fpm_conf || errorExit "Could not replace core user in php-fpm config"
    sed -i "$JFI_HOME_CORE_REPLACE" $fpm_conf || errorExit "Could not replace core home in php-fpm config"
}

THIRD_PARTY_DEPENDENCIES_CENTOS="$THIRD_PARTY_DEPENDENCIES_CENTOS php-fpm"
THIRD_PARTY_DEPENDENCIES_DEBIAN="$THIRD_PARTY_DEPENDENCIES_DEBIAN php5-fpm"
THIRD_PARTY_DEPENDENCIES_UBUNTU="$THIRD_PARTY_DEPENDENCIES_UBUNTU php5.6-fpm"
THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installPhpFpm"

# ------------------------------------------------------------------------------
# Configure php apc
# ------------------------------------------------------------------------------

installPhpAPC() {
    title "Installing php APC"
    log "Installing/Verifying php apc ..."
    
    local phpAPCPackage
    local phpAPCDependencies
    local packageHome="packages"
    local apcuHome="$packageHome/apcu"

    case ${DIST} in
        CentOS|RedHat)
            if [ ! -f "/usr/lib64/php/modules/apcu.so" ]; then
                mkdir -p "$apcuHome" && \
                [ -f "$packageHome/apcu.tar" ] && tar -xvf "$packageHome/apcu.tar" --directory "$apcuHome" >&6 || errorExit "could not install apcu"
                copyItem "apcu.ini" "$apcuHome" "/etc/php.d"
                copyItem "apcu.so" "$apcuHome" "/usr/lib64/php/modules" 755
                copyItem "php-pecl-apcu.xml" "$apcuHome" "/var/lib/pear/pkgxml"
                copyItem "apcu.reg" "$apcuHome" "/var/lib/pear/.registry/.channel.pecl.php.net"
            fi
        ;;
        Debian)
            if [ ! -f "/usr/lib/php5/20131226/apcu.so" ]; then
                mkdir -p "$apcuHome" && \
                [ -f "$packageHome/apcu.tar" ] && tar -xvf "$packageHome/apcu.tar" --directory "$apcuHome" >&6 || errorExit "could not install apcu"
                copyItem "apcu.ini" "$apcuHome/php5/mods-available" "/etc/php5/mods-available"
                copyItem "apc.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apc_api.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apc_bin_api.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apc_cache_api.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apc_lock_api.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apc_serializer.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apc_sma_api.h" "$apcuHome/include/php5/ext/apcu/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apcu.so" "$apcuHome/lib/php5/20131226" "/usr/lib/php5/20131226"
                copyItem "NOTICE" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "INSTALL.gz" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "README.Debian" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "README.md" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "TECHNOTES.txt.gz" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "TODO" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "apc.php" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "changelog.Debian.gz" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "changelog.gz" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "copyright" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "package.xml.gz" "$apcuHome/share/doc/php5-apcu" "/usr/share/doc/php5-apcu"
                copyItem "apcu.reg" "$apcuHome/share/php/.registry/.channel.pecl.php.net" "/usr/share/php/.registry/.channel.pecl.php.net"
            fi
            configurePHPAPC
        ;;
        Ubuntu)
            if [ ! -f "/usr/lib/php/20131226/apcu.so" ]; then
                mkdir -p "$apcuHome" && \
                [ -f "$packageHome/apcu.tar" ] && tar -xvf "$packageHome/apcu.tar" --directory "$apcuHome" >&6 || errorExit "could not install apcu"
                copyItem "php-apcu" "$apcuHome/share/doc" "/usr/share/doc"
                copyItem "apcu" "$apcuHome/include/php/20131226/ext/apcu" "/usr/include/php5/ext/apcu"
                copyItem "apcu.ini" "$apcuHome/php/5.6/mods-available" "/etc/php/5.6/mods-available"
                copyItem "20-apcu.ini" "$apcuHome/php/5.6/fpm/conf.d" "/etc/php/5.6/fpm/conf.d"
                copyItem "20-apcu.ini" "$apcuHome/php/5.6/cli/conf.d" "/etc/php/5.6/cli/conf.d"
                copyItem "apcu.so" "$apcuHome/lib/php/20131226" "/usr/lib/php/20131226"
            fi
            configurePHPAPC
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac
}

configurePHPAPC() {
    log "Adding apcu extension to php ini"

    # Add apcu extension
    appendString "extension=apcu.so" "$php_ini"
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installPhpAPC"

# ------------------------------------------------------------------------------
# Configure mongodb php lib
# ------------------------------------------------------------------------------

# installs mongodb php library and its dependencies
# expects two variables to be set with appropriate values,
installMongoDBPhpLibrary() {
    title "Installing / Verifying mongodb php library and mcrypt"
    log "Installing / Verifying mongodb php library and mcrypt (this may take several minutes)..."
    local mcryptDependency
    local phpcurlPackage
    local docLoc="/usr/share/doc"
    local packageHome="packages"
    local mongodbHome="$packageHome/mongodb"
    local mcryptHome="$packageHome/mcrypt"
    local curlHome="$packages/curl"

    case ${DIST} in
        CentOS|RedHat)
            if [ ! -f "/usr/lib64/php/modules/mongodb.so" ]; then
                mkdir -p "$mongodbHome" && \
                [ -f "$packageHome/mongodb.tar" ] && tar -xvf "$packageHome/mongodb.tar" --directory "$mongodbHome"  >&6 || errorExit "could not install mongodb"
                copyItem "share" "$mongodbHome" "/usr"
                copyItem "mongodb.so" "$mongodbHome" "/usr/lib64/php/modules" 755
                copyItem "mongodb.reg" "$mongodbHome" "/var/lib/pear/.registry/.channel.pecl.php.net"
            fi

            mcryptDependency="libmcrypt.rpm"
            installPackage "${mcryptDependency}"
            if [ ! -f "/usr/lib64/php/modules/mcrypt.so" ]; then
                mkdir -p "$mcryptHome" && \
                [ -f "$packageHome/mcrypt.tar" ] && tar -xvf "$packageHome/mcrypt.tar" --directory "$mcryptHome" >&6 || errorExit "could not install mcrypt"
                copyItem "mcrypt.ini" "$mcryptHome" "/etc/php.d"
                copyItem "mcrypt.so" "$mcryptHome" "/usr/lib64/php/modules" 755
            fi

        ;;
        Debian)
            if [ ! -f "/usr/lib/php5/20131226/mongodb.so" ]; then
                mkdir -p "$mongodbHome" && \
                [ -f "$packageHome/mongodb.tar" ] && tar -xvf "$packageHome/mongodb.tar" --directory "$mongodbHome" >&6 || errorExit "could not install mongodb"
                copyItem "share" "$mongodbHome" "/usr"
                copyItem "mongodb.so" "$mongodbHome" "/usr/lib/php5/20131226" 644
                copyItem "LICENSE" "$mongodbHome/share/doc/php5-common/PEAR/mongodb" "/usr/share/doc/php5-common/PEAR/mongodb"
                copyItem "CREDITS" "$mongodbHome/share/doc/php5-common/PEAR/mongodb" "/usr/share/doc/php5-common/PEAR/mongodb"
                copyItem "README.md" "$mongodbHome/share/doc/php5-common/PEAR/mongodb" "/usr/share/doc/php5-common/PEAR/mongodb"
                copyItem "LICENSE" "$mongodbHome/share/doc/php5-common/PEAR/mongodb/mongodb" "/usr/share/doc/php5-common/PEAR/mongodb/mongodb"
                copyItem "CREDITS" "$mongodbHome/share/doc/php5-common/PEAR/mongodb/mongodb" "/usr/share/doc/php5-common/PEAR/mongodb/mongodb"
                copyItem "README.md" "$mongodbHome/share/doc/php5-common/PEAR/mongodb/mongodb" "/usr/share/doc/php5-common/PEAR/mongodb/mongodb"
                copyItem "mongodb.reg" "$mongodbHome" "/usr/share/php/.registry/.channel.pecl.php.net"
            fi

            mcryptDependency="libmcrypt4_2.5.8.deb"
            installPackage "${mcryptDependency}"

            if [ ! -f "/usr/lib/php5/20131226/mcrypt.so" ]; then
                mkdir -p "$mcryptHome" && \
                [ -f "$packageHome/mcrypt.tar" ] && tar -xvf "$packageHome/mcrypt.tar" --directory "$mcryptHome"  >&6 || errorExit "could not install mcrypt"
                copyItem "control" "$mcryptHome/share/bug/php5-mcrypt" "/usr/share/bug/php5-mcrypt"
                copyItem "script" "$mcryptHome/share/bug/php5-mcrypt" "/usr/share/bug/php5-mcrypt"
                copyItem "php5-mcrypt" "$mcryptHome/share/doc" "/usr/share/doc"
                copyItem "mcrypt.ini" "$mcryptHome/share/php5/mcrypt" "/usr/share/php5/mcrypt"
                copyItem "mcrypt.so" "$mcryptHome" "/usr/lib/php5/20131226" 644
            fi

            if [ ! -f "/usr/lib/php5/20131226/curl.so" ]; then
                mkdir -p "$curlHome" && \
                tar -xvf "$packageHome/curl.tar" --directory "$curlHome"  >&6 2>&1 || errorExit "could not install php curl"
                copyItem "curl.ini" "$curlHome/php5/mods-available" "/etc/php5/mods-available"
                copyItem "20-curl.ini" "$curlHome/php5/fpm/conf.d" "/etc/php5/fpm/conf.d"
                copyItem "20-curl.ini" "$curlHome/php5/cli/conf.d" "/etc/php5/cli/conf.d"
                copyItem "php5-curl" "$curlHome/share/doc" "/usr/share/doc"
                copyItem "curl.so" "$curlHome/lib/php5/20131226" "/usr/lib/php5/20131226" 644
            fi
        ;;
        Ubuntu)
            if [ ! -f "/usr/lib/php5/20131226/mongodb.so" ]; then
                mkdir -p "$mongodbHome" && \
                [ -f "$packageHome/mongodb.tar" ] && tar -xvf "$packageHome/mongodb.tar" --directory "$mongodbHome" >&6 || errorExit "could not install mongodb"
                copyItem "mongodb" "$mongodbHome/share/php/docs" "/usr/share/php/docs"
                copyItem "mongodb.so" "$mongodbHome/lib/php/20131226" "/usr/lib/php/20131226" 644
            fi

            mcryptDependency="libmcrypt4_2.5.8.deb"
            installPackage "${mcryptDependency}"

            if [ ! -f "/usr/lib/php/20131226/mcrypt.so" ]; then
                mkdir -p "$mcryptHome" && \
                [ -f "$packageHome/mcrypt.tar" ] && tar -xvf "$packageHome/mcrypt.tar" --directory "$mcryptHome"  >&6 || errorExit "could not install mcrypt"
                copyItem "mcrypt.ini" "$mcryptHome/php/5.6/mods-available" "/etc/php/5.6/mods-available"
                copyItem "20-mcrypt.ini" "$mcryptHome/php/5.6/fpm/conf.d" "/etc/php/5.6/fpm/conf.d"
                copyItem "20-mcrypt.ini" "$mcryptHome/php/5.6/cli/conf.d" "/etc/php/5.6/cli/conf.d"
                copyItem "php5.6-mcrypt" "$mcryptHome/share/doc" "/usr/share/doc"
                copyItem "mcrypt.so" "$mcryptHome/lib/php/20131226" "/usr/lib/php/20131226" 644
            fi

            if [ ! -f "/usr/lib/php/20131226/curl.so" ]; then
                mkdir -p "$curlHome" && \
                tar -xvf "$packageHome/curl.tar" --directory "$curlHome"  >&6 2>&1 || errorExit "could not install php curl"
                copyItem "curl.ini" "$curlHome/php/5.6/mods-available" "/etc/php/5.6/mods-available"
                copyItem "20-curl.ini" "$curlHome/php/5.6/fpm/conf.d" "/etc/php/5.6/fpm/conf.d"
                copyItem "20-curl.ini" "$curlHome/php/5.6/cli/conf.d" "/etc/php/5.6/cli/conf.d"
                copyItem "php5.6-curl" "$curlHome/share/doc" "/usr/share/doc"
                copyItem "curl.so" "$curlHome/lib/php/20131226" "/usr/lib/php/20131226" 644
            fi
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac

    configurePHPMongoDB 
}

configurePHPMongoDB() {
    log "Adding mongo and mcrypt extension to php ini"

    # Add mongodb extension
    appendString "extension=mongodb.so" "$php_ini"

    if [[ "${DIST}" == "Debian" ]]; then
        # Add mcrypt extension
        appendString "extension=mcrypt.so" "$php_ini"
    fi
}

THIRD_PARTY_LIBRARIES="$THIRD_PARTY_LIBRARIES installMongoDBPhpLibrary"
THIRD_PARTY_DEPENDENCIES_DEBIAN="$THIRD_PARTY_DEPENDENCIES_DEBIAN libltdl7"
THIRD_PARTY_DEPENDENCIES_UBUNTU="$THIRD_PARTY_DEPENDENCIES_UBUNTU libltdl7"

# ------------------------------------------------------------------------------
# Configure JFMC
# ------------------------------------------------------------------------------

JFMC_PKG="jfmc"

genInternalCerts(){
    log "Generating internal certificates"
    local jfmcEtc=${JFMC_DATA}/etc
    local jfmcSecurity=${jfmcEtc}/security/
    local insightSecurity=${JFMC_DATA}/insight/etc/security/
    for folder in ${jfmcSecurity} ${insightSecurity}
    do
        if [ ! -d ${folder} ]; then
            mkdir -p ${folder}
        fi
    done
    local storePassword=$(cat /dev/urandom | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 16)
    ${SEED_DATA}/genCerts.sh ${storePassword} ${jfmcSecurity} ${insightSecurity} && \
    echo ${storePassword} > ${jfmcSecurity}/passwd && \
    echo ${storePassword} > ${insightSecurity}/passwd
}

mcOldVersionCleanUp() {
    local packName="jfrog-mission-control"
    isInstalled "$packName"
    if [ $? -eq 0 ]; then
        case ${DIST} in
        CentOS|RedHat)
            rpm -e "$packName" 2>/dev/null
        ;;
        Debian|Ubuntu)
            dpkg --remove "$packName" 2>/dev/null
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
        esac
    fi
}

installJFMC() {
    title "Installing Mission control"
    local packName='jfmc'
    local isInstalled="no"
    local packFile
    case ${DIST} in
        CentOS|RedHat)
            packFile="${JFMC_PKG}.rpm"
        ;;
        Debian|Ubuntu)
            packFile="${JFMC_PKG}.deb"
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac

    # backward compatibility statement to handle merge of jfmc and mission-control RPM/DEB
    mcOldVersionCleanUp

    # pass 'yes' do a thorough check before install 
    installPackage "${packFile}" "yes" "upgrade"

    updateModifiedJFMCPorts

    if [ ${JFMC_DATA_CHANGED} == true ]; then
        sed -i 's|'${JFMC_DATA_DEFAULT}'|'${JFMC_DATA}'|g' "${JFMC_MASTER_ENV}"
        source ${JFMC_MASTER_ENV}
        whoOwn=$(stat --format '%U' "${JFMC_DATA}")
        if [ ${whoOwn} != "${JFMC_USER}" ]; then
            chown -R ${JFMC_USER}:${JFMC_GROUP} ${JFMC_DATA}
        fi
    fi 

    [ -d /opt/jfrog/jfmc ] && rm -fr /opt/jfrog/jfmc || true

    ${JFMC_HOME}/scripts/jfmc.sh deployServices

    genInternalCerts
}

# Update env file with updated ports list
# This expects MODIFIED_PORTS to be populated with env variables which were modified
updateModifiedJFMCPorts() {
    if [[ -z "$MANDATORY_PORT_LIST" || "$MANDATORY_PORT_LIST" == "" ]]; then
        return
    fi

    # load env variables in a hierarchical way - as in master => custom
    # setenv.sh represents master , where as tmp_env represents ports modified in this version
    [ -f "${JFMC_MASTER_ENV}" ]   && source "${JFMC_MASTER_ENV}"
    [ -f "${JFMC_MODIFIED_ENV}" ] && source "${JFMC_MODIFIED_ENV}" || return

    local PORT_LIST=($MANDATORY_PORT_LIST)
    local port_key=

    for port_key in "${PORT_LIST[@]}"
    do
        addToEnvFile "$port_key" "add_to_beggining"
    done
}

updateMCPort(){
    local mc_properties="${JFMC_DATA}/etc/mission-control.properties"
    if [[ ! -z "$JFMC_PORT" && "$JFMC_PORT" != "" && "$JFMC_PORT" != "8080" ]]; then
        [ -f "$mc_properties" ] && addOrReplaceProperty "server.port" "$JFMC_PORT" "$mc_properties"
    fi
}

POST_INSTALL_TASKS="$POST_INSTALL_TASKS updateMCPort"
THIRD_PARTY_DEPENDENCIES_CENTOS="$THIRD_PARTY_DEPENDENCIES_CENTOS net-tools"
THIRD_PARTY_DEPENDENCIES_DEBIAN="$THIRD_PARTY_DEPENDENCIES_DEBIAN net-tools"
THIRD_PARTY_DEPENDENCIES_UBUNTU="$THIRD_PARTY_DEPENDENCIES_UBUNTU net-tools"

# ------------------------------------------------------------------------------
# Main logic
# ------------------------------------------------------------------------------

#This is the main file responsible for the installation

INSTALLER_DIR="$( cd "$( dirname $0 )/" && pwd )"
pushd ${INSTALLER_DIR} >/dev/null 2>&1
SCRIPT_NAME="$(basename $0 | awk -F '.' '{print $1}')"
DATE=$(date +"%Y%m%d%H%M")

LOG_FILE_NAME="${SCRIPT_NAME}.${DATE}.log"
INSTALLATION_LOG_FILE="${INSTALLER_DIR}/${LOG_FILE_NAME}"
JFMC_HOME=/opt/jfrog/mission-control
JFMC_DATA_DEFAULT=/var/opt/jfrog/mission-control
SEED_DATA="./seed_data"

JFMC_MASTER_ENV="${JFMC_HOME}/scripts/setenv.sh"
JFMC_MODIFIED_ENV="${INSTALLER_DIR}/jfmcInstallConf.sh"
IS_ENV_AVAILABLE=false
#Labels
ELASTIC_SEARCH_LABEL='Elasticsearch'
MONGO_LABEL='MongoDB'
POSTGRES_LABEL='Postgres'
MISSION_CONTROL_PACKAGE="jfrog-mission-control"

IS_UPGRADE=false
JFMC_DATA_CHANGED=false

checkUMask() {
    # Check user file-creation mode mask
    log "Checking the user file-creation mode mask (umask)"
    local valUmask=$(umask)
    if [[ "${valUmask}" =~ 0022|022|0002|002 ]]; then
        log "The system has a default umask setup, proceeding..."
    else
        log "To continue with Mission Control installation, allow access mode for new files and directories"
        log "Set umask as follows:"
        log "$ umask 022"
        log "Note: WE RECOMMEND RESTARTING MACHINE TO MAKE SURE THE CHANGE TAKES EFFECT"
        errorExit "Mission Control installation failed on umask mode"
    fi
}

isUpgrade() {
    case ${DIST} in
        CentOS|RedHat)
            rpm -qa | grep "jfmc" >&6
            if [ $? -eq 0 ]; then
                IS_UPGRADE=true
                INSTALLED_VER=$(rpm -qi --nosignature ${MISSION_CONTROL_PACKAGE} 2>/dev/null | grep Version | awk -F ': ' '{print $2}' | awk '{print $1}')
            fi
        ;;
        Debian|Ubuntu)
            # Check if this is an upgrade
            local status
            local currentState

            # get status of mission-control
            status=$(dpkg -l | grep "jfmc" | awk '{print $1}')
            # get second character of the response
            [[ ! -z $status ]] && currentState=${status:1:1} || currentState="Not Installed"
            
            # if currentState is 'i', consider it as installed
            if [[ "$currentState" == "i" ]]; then
                IS_UPGRADE=true
                INSTALLED_VER=$(dpkg-query -W -f='${Version}' ${MISSION_CONTROL_PACKAGE} 2>/dev/null)
            fi
        ;;
        *)
            errorExit "Distribution $DIST is not supported"
        ;;
    esac

    echo -n ""
}

setDataFolder() {
    if [ -d $JFMC_DATA_DEFAULT ]; then
        JFMC_DATA=${JFMC_DATA_DEFAULT}
    elif [[ $IS_UPGRADE != true ]]; then
        if [[ $TYPE_OF_INSTALLATION == "standard" ]];then
            JFMC_DATA=$JFMC_DATA_DEFAULT
        else
            log "Mission Control data folder must be set during installation"
        
            log "NOTE: If you are reinstalling Mission control, please ensure you choose \
the earlier installation's data folder or manually reset and remove 3rd party services like $POSTGRES_LABEL and $MONGO_LABEL. \n\
Not doing so may cause issues when the installation tries to seed data into these services" #Don't add a tab to this line
            
            log "Type the desired JFMC_DATA location or press Enter to accept the default" 
            getUserInput "Enter Mission Control data folder" "${JFMC_DATA_DEFAULT}"
            if [ "${users_choice}" != "${JFMC_DATA_DEFAULT}" ]; then
                JFMC_DATA_CHANGED=true
            fi
            JFMC_DATA=${users_choice:-${JFMC_DATA_DEFAULT}}
        fi
    else
        if [ ! -f "${JFMC_MASTER_ENV}" ]; then
            if [ -f ${JFMC_HOME}/scripts/setenvDefaults.sh ]; then
                cp ${JFMC_HOME}/scripts/setenvDefaults.sh "${JFMC_MASTER_ENV}" || exit $?
            fi 
        fi
        [ -f "${JFMC_MASTER_ENV}" ] && source "${JFMC_MASTER_ENV}"
    fi
    log "Checking for existence of Mission Control data folder"
    if [ -d ${JFMC_DATA} ]; then
        log "Mission Control data folder already exists on $JFMC_DATA"
        if [[ -f ${JFMC_DATA}/setenv.sh ]]; then
            # backward compatibility statement to handle merge of jfmc and mission-control
            sed -ie "s#/opt/jfrog/jfmc#${JFMC_HOME}#g" "${JFMC_DATA}"/setenv.sh

            source ${JFMC_DATA}/setenv.sh
            cp ${JFMC_DATA}/setenv.sh ${JFMC_DATA}/setenv.sh.backup
            cp ${JFMC_DATA}/setenv.sh ${JFMC_MODIFIED_ENV}
            IS_ENV_AVAILABLE=true
            warn "The file: ${JFMC_DATA}/setenv.sh has been backed up as ${JFMC_DATA}/setenv.sh.backup. \n\
Once the upgrade is complete, you may need to reconcile any manual changes you may have made to the file"
        fi
    else
        log "Creating Mission Control data folder on $JFMC_DATA"
        mkdir -p ${JFMC_DATA} || errorExit "Creating Mission Control data folder failed"
    fi
    export JFMC_LOGS="$JFMC_DATA/logs"
    JFMC_INSTALL_LOGS="$JFMC_DATA/installer"
    mkdir -p $JFMC_INSTALL_LOGS
}

checkPortsAvailability() {
    [ -f "${JFMC_MASTER_ENV}" ]   && source "${JFMC_MASTER_ENV}"
    [ -f "${JFMC_MODIFIED_ENV}" ] && source "${JFMC_MODIFIED_ENV}"
    
    # validate only mandatory ports for advanced installation and all ports for standard    
    if [[ $IS_ENV_AVAILABLE != true && "$TYPE_OF_INSTALLATION" == "standard" ]]; then
        [[ ! -z "$MANDATORY_PORT_LIST" && "$MANDATORY_PORT_LIST" != "" ]] && validatePorts "$MANDATORY_PORT_LIST" "error"
        [[ ! -z "$OPTIONAL_PORT_LIST"  && "$OPTIONAL_PORT_LIST"  != "" ]] && validatePorts "$OPTIONAL_PORT_LIST" "warning"
    elif [[ $IS_ENV_AVAILABLE != true && "$TYPE_OF_INSTALLATION" == "advanced" ]]; then
        [[ ! -z "$MANDATORY_PORT_LIST" && "$MANDATORY_PORT_LIST" != "" ]] && validatePorts "$MANDATORY_PORT_LIST" "error"
    fi    
}

determineTypeOfInstall() {
    log "Mission Control uses $ELASTIC_SEARCH_LABEL, $MONGO_LABEL and $POSTGRES_LABEL. The installer will install these automatically. \n\
    The original script supports external dbs, but this ansible automated installation hasnt it implemented yet."

    TYPE_OF_INSTALLATION="standard"
}

main() {

    # The logic below helps us redirect content we'd normally hide to the log file. 
    #
    # We have several commands which clutter the console with output and so use 
    # `cmd > /dev/null` - this redirects the command's output to null.
    # 
    # However, the information we just hid maybe useful for support. Using the code pattern
    # `cmd >&6` (instead of `cmd> >/dev/null` ), the command's output is hidden from the console 
    # but redirected to the installation log file
    # 
    exec 6>>$INSTALLATION_LOG_FILE

    # This also allows us to add a 'verbose' mode to the installer. If the installer is
    # invoked with the parameter `-v`, &6 is changed to redirect to the regular stdout making all 
    # the content we'd otherwise hide, visible in the console.
    while getopts ":v" opt; do
      case $opt in
        v)
            log "Running installer in verbose mode"
            exec 6>&1  
        ;;  
      esac
    done

    title "JFrog Mission Control Installation"

    log "This script will install JFrog Mission Control. After installation, logs can be found at $INSTALLATION_LOG_FILE"

	#Check required system settings
	checkLinuxDistribution
    checkSELinux
    checkPrerequisites
    
    local USER_END_INSTALLS
    case $DIST in
        CentOS|RedHat)
            USER_END_INSTALLS="$THIRD_PARTY_DEPENDENCIES_CENTOS"
        ;;
        Debian)
            USER_END_INSTALLS="$THIRD_PARTY_DEPENDENCIES_DEBIAN"
        ;;
        Ubuntu)
            USER_END_INSTALLS="$THIRD_PARTY_DEPENDENCIES_UBUNTU"
        ;;
    esac
	checkPrerequisitesSoftware "$USER_END_INSTALLS"
	checkUMask
	sleep 2

    isUpgrade

	# Pre-installation setups
    determineTypeOfInstall
    IS_ENV_AVAILABLE=$IS_UPGRADE
    setDataFolder #IMPORTANT: Any previous env variables are loaded here from setenv.sh

    checkPortsAvailability
    
    #Third party libraries
    THIRD_PARTY_LIBRARIES=($THIRD_PARTY_LIBRARIES)
    for installCommand in "${THIRD_PARTY_LIBRARIES[@]}"
    do
        log "Invoking ${installCommand}" >&6 2>&1
        eval "${installCommand}"
    done

    #Install JFMC services (NOTE: The order below is important)
    installJFMC 

    #Third party libraries' env variables are now put into setenv
    DEPENDENT_SERVICES=""
    POST_INSTALL_TASKS=($POST_INSTALL_TASKS)
    for cleanupCommand in "${POST_INSTALL_TASKS[@]}"
    do
        log "Invoking ${cleanupCommand}" >&6 2>&1
        eval "${cleanupCommand}"
    done

    addToEnvFile "DEPENDENT_SERVICES"

    #Copy the setenv file to the data folder (to ensure it remains even if mission-control is uninstalled)
    cp ${JFMC_HOME}/scripts/setenv.sh ${JFMC_DATA}/setenv.sh

    # Restore LC_CTYPE from env, fix for mac users (via ssh), which execute the command with sudo
    if [ -z ${LC_CTYPE_BACKUP} ]; then
        export LC_CTYPE=${LC_CTYPE_BACKUP}
    fi

    log "Installation complete. Logs can be found at [$INSTALLATION_LOG_FILE]"
    log "Start JFrog Mission Control using [$JFMC_HOME/scripts/jfmc.sh start]"
}

#reference https://stackoverflow.com/questions/31551115/in-bash-tee-is-making-function-variables-local-how-do-i-escape-this
exec 3> >(INSTALLATION_LOG_FILE="$INSTALLATION_LOG_FILE" flock "$INSTALLATION_LOG_FILE" -c 'exec tee "$INSTALLATION_LOG_FILE"') # open output to log
main >&3 2>&3                                   # run function, sending stdout/stderr to log
exec 3>&-                                       # close output
flock "$INSTALLATION_LOG_FILE" -c true          # wait for tee to finish flushing and exit

NEW_LOG_LOC="$JFMC_DATA/logs/$LOG_FILE_NAME"
mkdir -p $(dirname "$NEW_LOG_LOC")
cp "$INSTALLATION_LOG_FILE" $NEW_LOG_LOC

echo -e "\033[32mNOTE: Installation log file can be found here: $NEW_LOG_LOC\033[0m"
exit $?

{% endraw %}