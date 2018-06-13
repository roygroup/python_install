#!/bin/bash

# Python/Numpy linked to Intel MKL or openBLAS build script
# version 0.2.0


# # # # # # # USER INPUT # # # # # # #
# HELLO USER!
# PLEASE CHOOSE A DIRECTORY WHERE Python WILL BE INSTALLED
ROOT_DIRECTORY=$HOME/.dev
# # # # # # # USER INPUT # # # # # # #

#lang specific details
export LANG=C
export LC_ALL=C
set -e

# error codes
E_WRONGKERNEL=83    # wrong kernel
E_WRONGARCH=84      # wrong architecture
E_WRONGARS=85       # Arguments wrong error
E_XCD=86            # Can't change directory?
E_NOTROOT=87        # Non-root exit error
E_DOWNLOAD=88       # Failed to download necessary files
tar_error_string="Failed to untar: %s\nIs this hyperlink broken: %s\nIt is required that you can download all packages before the installer can run.\n"

#HTTP status codes
HTTP_NOT_FOUND=404
HTTP_OK=200

#FTP status codes
FTP_NOT_FOUND=550
FTP_OK=350


# list of sharcnet / computecanada clusters
cluster_hostnames=(
                    "orc-login" # orca
                    "gra-login"
                    'cedar[0-9]'
                   )

#---------------------------------------------------------------------------------------------------------
#---------------------------------------------- FUNCTIONS ------------------------------------------------
#---------------------------------------------------------------------------------------------------------

# keep all download options contained
function download() {
    # -s Silent or quiet mode. Don't show progress meter or error messages. Makes Curl mute.
    #    It will still output the data you ask for, potentially even to the terminal/stdout unless you redirect it.
    # -S When used with -s it makes curl show an error message if it fails.
    # -L Handles redirection, makes curl redo the request on the new location
    # -O Write output to a local file named like the remote file we get.
    # -I curl returns the servers HTTP headers, not the page data
    #
    # first we check the header to make sure the link is valid,
    RESPONSE_CODE=$(curl -s -o /dev/null -IL -w "%{http_code}" "${1}")

    if [[ RESPONSE_CODE -eq HTTP_OK ]] || [[ RESPONSE_CODE -eq FTP_OK ]]; then
        # the link is valid and we proceed with the download
        curl -s -SOL "${1}"
    elif [[ RESPONSE_CODE -eq HTTP_NOT_FOUND ]] || [[ RESPONSE_CODE -eq FTP_NOT_FOUND ]]; then
        # the link is invalid and we notify the user
        printf "Header code was invalid, please manually check the following hyperlink.\n%s\nIt is possible that the version number is out of date.\n" "${1}"
        exit ${E_DOWNLOAD}
    else
        # undefined result, notify user
        printf "Header code was ambigious, please check the validity of this url: \n%s\n" "${1}"
    fi
}


# let the user know if we failed to get to the correct directory, wrap cd in an "error checking function"
function change_dir()   {
    cd ${1} || {
        printf "Cannot change to directory: %s\n" "${1}"
        exit ${E_XCD};
    }
}


function check_if_sharcnet_or_compute_canada() {
    # check if you are running on computecanada or sharcnet cluster
    # if so we need to print out a message to the user
    hostname=$(hostname)
    for str in ${cluster_hostnames[@]}; do
        if [[ ${hostname} =~ ${str} ]]; then
            echo "It appears that you are running the install script on a login node of a SHARCNET or compute canada cluster.
    Please note that to install on these clusters is a two step process.
    First you need to run the script on the head node until the downloads are finished, then exit the script with Ctrl+D.
    Next you should execute the script in an interactive session, or as a job with sbatch.
    Do you understand?"
            DOWNLOAD_ONLY=true
            select yn in "Yes" "No"; do
                case $yn in
                    Yes ) break;;
                    No ) echo "Please contact someone in the group"; exit 0;;
                esac
            done
        fi
    done
}


function check_architecture()   {
    Architecture=$(uname -m)
    case "$Architecture" in
        x86)
            Architecture="x86"
            ;;
        ia64)
            Architecture="ia64"
            ;;
        i?86)
            Architecture="x86"
            ;;
        amd64)
            Architecture="amd64"
            ;;
        x86_64)
            Architecture="x86_64"
            ;;
        sparc64)
            Architecture="sparc64"
            ;;
        * )
            printf "Your Architecture %s -> IS NOT SUPPORTED\n" "${Architecture}"
            exit ${E_WRONGARCH}
            ;;
    esac
    printf "Operating System Architecture: %s\n" "${Architecture}"
}


function check_operating_system()   {
    # check what OS we are running
    # get the kernel Name
    printf "\n     ===============  machine info  ===============     \n"
    Kernel=$(uname -s)
    case "$Kernel" in
        Linux)
            Kernel=$(lsb_release -si)
            Kernel=${Kernel,,}
            INSTALL_PIP_FLAG=true

            # set the install directory
            LINUX_RELEASE_NUMBER=$(lsb_release -sr)
            INSTALL_DIRECTORY="${ROOT_DIRECTORY}/${Kernel}_${LINUX_RELEASE_NUMBER}"
            ;;

        Darwin)
            MAC_VERSION=$(sw_vers -productVersion)
            Kernel="OSX $MAC_VERSION"
            export GCC=/usr/bin/clang

            # set the install directory
            INSTALL_DIRECTORY="${ROOT_DIRECTORY}/OSX_${MAC_VERSION}"

            # handle gfortran
            case "$MAC_VERSION" in
                10.13*)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-6.3-Sierra.dmg           ;;
                10.12*)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-6.3-Sierra.dmg           ;;
                10.11*)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-6.1-ElCapitan.dmg        ;;
                10.10*) # (OS X 10.10)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-5.2-Yosemite.dmg         ;;
                10.9*)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-4.9.0-Mavericks.dmg      ;;
                10.8*)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-4.8.2-MountainLion.dmg   ;;
                10.7*)
                    GFORTAN_LINK=http://coudert.name/software/gfortran-4.8.2-Lion.dmg           ;;
                *)
                    printf "You need to find a source for gfortran to install on you iMac\n"
                    exit 0
                    ;;
            esac

            # make sure xcode is installed and up to date
            echo "Is xcode installed and up to date?"
            select yn in "Yes" "No"; do
                case $yn in
                    Yes ) break;;
                    No ) echo "Please install/update xcode before running the script again"; exit 0;;
                esac
            done


            set +e
            # make sure you have openssl installed for pip
            if [[ $MAC_VERSION == 1[0-9].1* ]]; then
                which -s brew
                if [[ $? != 0 ]] ; then # then brew doesn't exist
                    # let the user install homebrew
                    echo "You are running OSX and you don't have brew"
                    echo "This means that you will not have pip because openssl is not supported in 10.10+"
                    echo "If you want pip please exit and install brew"
                    echo "Are you sure you wish to proceed?"
                    select yn in "Yes" "No"; do
                        case $yn in
                            Yes ) break;;
                            No ) exit;;
                        esac
                    done
                else
                    # brew does exist!
                    brew ls --versions openssl
                    if [[ $? != 0 ]] ; then # but no openssl
                        echo "Apparently you don't have openssl installed through brew"
                        echo "Can I install openssl using brew?"
                        select yn in "Yes" "No"; do
                            case $yn in
                                Yes ) brew install openssl; brew link --force openssl; break;;
                                No ) exit;;
                            esac
                        done
                    else
                        # openssl installed! joy!
                        echo "Good you have openssl installed through brew, pip will be installed successfully"
                        INSTALL_PIP_FLAG=true
                    fi
                fi
            else
                # if you have an ealier version of OSX (before 10.10) then openssl should be native
                # and you won't need another version, from brew for example
                INSTALL_PIP_FLAG=true
            fi
            set -e
            # lazy way to force the installer to use clang instead of an independent version of gcc installed in /usr/local/bin
            export PATH="/usr/bin:$PATH"
            ;;
        # default case
        * )
            printf "Your Operating System %s -> IS NOT SUPPORTED\n" "${Kernel}"
            exit ${E_WRONGKERNEL}
            ;;
    esac
    printf "Operating System Kernel: %s\n" "${Kernel}"
}


function check_gfortran()   {
    # lets check if you have gfortran
    if [[ "$(command -v gfortran)" ]]; then
        printf "\nIt seems that you have gfortran\n"
        # HAS_GFORTRAN=true
    else
        printf "\nYou do not have gfortran! You will not be able to compile openBLAS.\n"
        printf "Please download and install gfortran from this link:\n%s\nNote that this requires administrative privilages!\n" "$GFORTAN_LINK"
        printf "If you have already installed an older version of gfortran please remove it with the following command:\n%s\n" \
        "sudo rm -r /usr/local/gfortran /usr/local/bin/gfortran"
        # HAS_GFORTRAN=false
        exit 0
    fi
}


function make_directories()   {
    # create the directories that we will be working in
    mkdir -p ${ROOT_DIRECTORY}
    mkdir -p ${DOWNLOAD_DIRECTORY}
    mkdir -p ${LOG_DIRECTORY}
    mkdir -p ${INSTALL_DIRECTORY}
    printf "Succesfully made directories: \n%s\n%s\n%s\n%s\n\n" "${ROOT_DIRECTORY}" "${DOWNLOAD_DIRECTORY}" "${LOG_DIRECTORY}" "${INSTALL_DIRECTORY}"
}


function install_programs()   {
    # install the programs
    for (( i=0; i<${arraylength}; i++ )); do
        if [[ "$1" -le "$i" ]]; then
            printf "Attempting to build and install %s\n" "${hyperlink_names[$i]}"
            {
                install_function "$i"
            } > "$LOG_DIRECTORY/${hyperlink_names[$i]}log" 2>&1
            change_dir ..
            printf "%s successfully installed\n" "${hyperlink_names[$i]}"
        else
            printf "Assuming %s is already installed\n" "${hyperlink_names[$i]}"
        fi
    done
}


# for readability
function exit_on_error() {
    echo "$1" >&3;
    exit 0;
}


# the specific installation options
function install_function() {
    case "$1" in
        0) # sqlite MUST be installed before python
            change_dir "${DOWNLOAD_DIRECTORY}"
            download https://www.sqlite.org/${sqlite_version}.tar.gz
            tar_name=$(echo $sqlite_version|cut -d'/' -f 2)
            tar -xvf ${tar_name}.tar.gz
            change_dir "${DOWNLOAD_DIRECTORY}/${tar_name}"
            ./configure --prefix="$INSTALL_DIRECTORY" || exit_on_error "Failed to configure sqlite, check the logs"
            make clean  # if we are re-runing the script we should start fresh
            make -j9 || exit_on_error "Failed to make sqlite, check the logs"
            make -j9 install || exit_on_error "Failed to install sqlite, check the logs"
            ;;

        1) # Python
            change_dir "${DOWNLOAD_DIRECTORY}"
            download https://www.python.org/ftp/python/${python_version}/Python-${python_version}.tgz
            tar -xvf Python-${python_version}.tgz
            change_dir "${DOWNLOAD_DIRECTORY}/Python-${python_version}"
            if [ "$INSTALL_PIP_FLAG" ] ; then
                echo "Pip will be installed"
                PIP_OPTION=install
                # this is necessary for pip installation on OSX
                # temporary hack, considering building openssl in the future
                if [[ "$Kernel" == OSX* ]] ; then
                    export LDFLAGS=-L/usr/local/opt/openssl/lib
                    export CPPFLAGS=-I/usr/local/opt/openssl/include
                    export PKG_CONFIG_PATH=/usr/local/opt/openssl/lib/pkgconfig
                    export PATH="/usr/local/opt/openssl/bin:$PATH"
                fi
            else
                echo "No pip installed"
                PIP_OPTION=no
            fi
            # do the install
            ./configure --prefix="$INSTALL_DIRECTORY" --with-ensurepip=${PIP_OPTION} || exit_on_error "Failed to configure python, check the logs"
            make clean  # if we are re-runing the script we should start fresh
            make -j9 || exit_on_error "Failed to make python, check the logs"
            make -j9 install || exit_on_error "Failed to install python, check the logs"
            ;;

        2) # openBLAS - should never occur now
            change_dir "${DOWNLOAD_DIRECTORY}"
            if [ ! -d "${DOWNLOAD_DIRECTORY}/OpenBLAS" ] ; then
                git clone https://github.com/xianyi/OpenBLAS.git
            fi
            change_dir "${DOWNLOAD_DIRECTORY}/OpenBLAS"
            git checkout "${openBLAS_version}"
            make clean
            # build options can be changed to user preference
            make FC=gfortran DYNAMIC_ARCH=1 USE_THREAD=1 NUM_THREADS=16 || exit_on_error "Failed to make openBLAS, check the logs"
            make PREFIX="$INSTALL_DIRECTORY" install || exit_on_error "Failed to install openBLAS, check the logs"
            ;;

        3) # Numpy + Scipy
            ${PIP} install cython # currently this is necessary
            change_dir "${DOWNLOAD_DIRECTORY}"
            if [ ! -d "${DOWNLOAD_DIRECTORY}/numpy" ] ; then
                git clone https://github.com/numpy/numpy
            fi
            change_dir "${DOWNLOAD_DIRECTORY}/numpy"
            git clean -xdf  # remove all possible previous build files
            git checkout master
            git pull
            git checkout "${numpy_version}"  # change this as appropriate when Numpy updates
            # requires site.cfg located in DOWNLOAD_DIRECTORY
            # see this url (LOOK AT THE BOTTOM) for site.cfg composition
            # https://software.intel.com/en-us/articles/numpyscipy-with-intel-mkl
            #
            # 'library_dirs = $INSTALL_DIRECTORY/intel/compilers_and_libraries_2018/linux/mkl/lib/intel64_lin\n'
            # 'include_dirs= $INSTALL_DIRECTORY/intel/compilers_and_libraries_2018/linux/mkl/include\n'
            # 'mkl_libs = mkl_def, mkl_intel_lp64, mkl_gnu_thread, mkl_core, mkl_mc3\n'
            # 'lapack_libs = mkl_def, mkl_intel_lp64, mkl_gnu_thread, mkl_core, mkl_mc3\n'
            SITE_CFG_STRING="
            [mkl]
            library_dirs = $INSTALL_DIRECTORY/intel/mkl/lib/intel64
            include_dirs = $INSTALL_DIRECTORY/intel/mkl/include
            mkl_libs = mkl_rt
            lapack_libs =
            [openblas]
            libraries = openblas
            library_dirs = ${INSTALL_DIRECTORY}/lib
            include_dirs = ${INSTALL_DIRECTORY}/include
            runtime_library_dirs = ${INSTALL_DIRECTORY}/lib
            "
            echo "$SITE_CFG_STRING" > ./site.cfg
            # check that there are 12 lines
            [[ "$(cat ./site.cfg | wc -l )" == 12 ]] || exit_on_error "There is something wrong with the site.cfg file -- it is not 12 lines-- make sure it is properly constructed"
            # ============= build options can be changed to user preference
            if [ -d "${INSTALL_DIRECTORY}/intel/mkl/" ] && \
               [ -a "${INSTALL_DIRECTORY}/intel/mkl/bin/mklvars.sh" ] && \
               [ -a "${INSTALL_DIRECTORY}/intel/mkl/bin/mklvars.csh" ] ; then
                # == if the intel libraries are available (we make a lot of assumptions here - no testing)
                if hash icc 2>/dev/null; then
                    # if the intel compiler icc exists
                    export CFLAGS='-O3 -g -fPIC -fp-model strict -fomit-frame-pointer -xhost'
                    export LDFLAGS='-lmkl_intel_ilp64 -lmkl_core -lgomp -lpthread -lm  -ldl'
                    ${PYTHON} setup.py config --compiler=intelem --fcompiler=intelem build_clib --compiler=intelem --fcompiler=intelem build_ext --compiler=intelem --fcompiler=intelem install || exit_on_error "Failed to configure numpy with the intel MKL libraries, check the logs"
                    # ${PYTHON} setup.py config --compiler=intelem build_clib --compiler=intelem build_ext --compiler=intelem|| exit_on_error "Failed to configure numpy with the intel MKL libraries, check the logs"
                else
                    # otherwise we have to use gcc or gfortran
                    export CFLAGS="-fopenmp -m64 -mtune=native -O3 -Wl,--no-as-needed"
                    export CXXFLAGS="-fopenmp -m64 -mtune=native -O3 -Wl,--no-as-needed"
                    export LDFLAGS="-ldl -lm -lpthread -lgomp"
                    export FFLAGS="-fopenmp -m64 -mtune=native -O3"
                    export MKL_THREADING_LAYER=GNU
                    # export LDFLAGS='-lm -lpthread -lgomp'
                    # export PATH=$PATH=$INSTALL_DIRECTORY/intel/mkl/bin:"${PATH}"
                    # export LD_LIBRARY_PATH=$HOME/.dev/ubuntu_18.04/intel/mkl/lib/intel64_lin:"${LD_LIBRARY_PATH}"
                    ${PYTHON} setup.py build --fcompiler=gnu95 || exit_on_error "Failed to build numpy with IntelMKL using gcc, check the logs"
                fi
            else
                # == if they are not
                ${PYTHON} setup.py build --fcompiler=gnu95 || exit_on_error "Failed to configure numpy with openBLAS, check the logs"
            fi
            # =============install numpy
            ${PYTHON} setup.py install --prefix="$INSTALL_DIRECTORY" || exit_on_error "Failed to install numpy, check the logs"

            # ============= and now we can install scipy, numpy shows it where openBLAS/intelMKL is located
            ${PIP} install scipy || exit_on_error "Failed to install scipy, check the logs"
            ;;

        4) # ghostscript
            change_dir "${DOWNLOAD_DIRECTORY}"
            tar -xvf ${ghostscript_version}.tar.gz
            change_dir "${DOWNLOAD_DIRECTORY}"/"${ghostscript_version}"
            ./configure --prefix="$INSTALL_DIRECTORY" || exit_on_error "Failed to configure ghostscript, check the logs"
            make clean  # if we are re-runing the script we should start fresh
            make -j9 || exit_on_error "Failed to make ghostscript, check the logs"
            make -j9 install || exit_on_error "Failed to install ghostscript, check the logs"
            ;;

        *)
            printf "Install loop did something weird, why is the counter ${1} greater than 2?\n"
            exit 0
            ;;


    esac
}

#---------------------------------------------------------------------------------------------------------
#---------------------------------------- INSTALL LOCAL PROGRAMS -----------------------------------------
#---------------------------------------------------------------------------------------------------------

# Flags - default is false - check_operating_system() will set to true if certain conditions are met
INSTALL_PIP_FLAG=false

# the directories we will be installing to
INSTALL_DIRECTORY="$ROOT_DIRECTORY" # will be modified later
DOWNLOAD_DIRECTORY="$ROOT_DIRECTORY"/downloads
LOG_DIRECTORY="$ROOT_DIRECTORY"/logs

# where the script is located
SCRIPT_NAME="${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}"
SCRIPT_DIR="$(dirname "${SCRIPT_FILE}")"

# the name of the log file
LOG_FILE="$SCRIPT_DIR/logfile"      # for now the current directory

# make sure the log file actually exists
touch "$LOG_FILE"

# see this post for explanation on how exec is working
# https://unix.stackexchange.com/questions/80988/how-to-stop-redirection-in-bash?utm_medium=organic&utm_source=google_rich_qa&utm_campaign=google_rich_qa
exec 3>&1 4>&2
# redirect all stdout and stderr to the log file
exec > >(tee "$LOG_FILE") 2>&1

# execute functions
check_architecture
check_operating_system
check_gfortran
make_directories
check_if_sharcnet_or_compute_canada

# these need to be after check_operating_system since we change INSTALL_DIRECTORY
PYTHON="$INSTALL_DIRECTORY"/bin/python3  # where python3 will be located
CYTHON="$INSTALL_DIRECTORY"/bin/cython  # where cython will be located
PIP="$INSTALL_DIRECTORY"/bin/pip3 # where pip3 will be located

change_dir "${DOWNLOAD_DIRECTORY}"
declare -a hyperlink_names  # the generic names of the packages we require
# hyperlink_names=( SQLite3 Python openBLAS Numpy )
hyperlink_names=( SQLite3 Python openBLAS Numpy ghostscript)
arraylength=${#hyperlink_names[@]} # the number of packages to install

# select versions of the programs
# sqlite_version="2017/sqlite-autoconf-3210000"
sqlite_version="2018/sqlite-autoconf-3240000"
python_version="3.6.5"
openBLAS_version="v0.2.20"
numpy_version="v1.14.5"
ghostscript_version="ghostscript-9.23"

if [[ $DOWNLOAD_ONLY = true ]]; then
    printf "It appears we are on a head node, execution will stop here, you must run the script in an interactive session or submit the job to the queue using sbatch/qsub/srun.\n"
    exit
fi

# the magic - assume that intel MKL is installed
#---------------------------------------------------------------------------------------------------------
install_programs "$1"
#---------------------------------------------------------------------------------------------------------

printf "Everything is done, please check the following output to make sure Numpy found the intel MKL installation\n"
${PYTHON} -c "import numpy as np
np.__config__.show()"
printf "Now Exiting the scipt\n"
exit 0




