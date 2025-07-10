#!/bin/bash
# Copyright (c) 2018 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public License,
# version 2 (GPLv2). There is NO WARRANTY for this software, express or
# implied, including the implied warranties of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
# along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.
#
# Red Hat trademarks are not licensed under GPLv2. No permission is
# granted to use or replicate Red Hat trademarks that are incorporated
# in this software or its documentation.
#
# written by whayutin@redhat.com & jmolet@redhat.com

function usage()
{
cat << USAGETEXT
This script will reserve a beaker box using bkr workflow-simple.
Note: Do NOT pass --task=/distribution/reservesys as an argument to this script.  It is automatically included.

Available options are:
  --debugxml                                 Preforms a dryrun and prints out the job xml
  --help                                     Prints this message and then exits
  --ignore-avc-error                         Ignores SELinux AVC errors
  --kspackage=PACKAGE or @GROUP or -@GROUP   Package or group to include/exclude during the kickstart
  --recipe_option=RECIPE_OPTION              Adds RECIPE_OPTION to the <recipe> section
  --timeout=MINUTES                          The timeout in minutes to wait for a beaker box (default:180 =3hours)
  --reservetime=SECONDS                      Return the system SECONDS after being reserved (default:86400 =24hours)

The following options are avalable to bkr workflow-simple:
$(bkr workflow-simple --help | tail -n +3 | grep -v "\-\-help")
USAGETEXT
}

DEBUGXML=false
FAMILY_NAME=""
IGNORE_AVC_ERROR=false
IGNORE_PROBLEMS=false
KSPKGS=""
PASSWORD=""
ROPTS=""
TASKS=""
TIMEOUT="180"
RESERVETIME="" # the Beaker default is 86400 =24hours
TOTAL_HOSTS=0
USERNAME=""

for arg do
  shift
  case $arg in
      --help)
        usage
        exit 0
        ;;
      --debugxml)
        DEBUGXML=true
        ;;
      --timeout=*)
        TIMEOUT=${arg//--timeout=/}
        ;;
      --reservetime=*)
        RESERVETIME=${arg//--reservetime=/}
        ;;
      --username=*)
        USERNAME=$arg
        set -- "$@" "$arg"
        ;;
      --password=*)
        PASSWORD=$arg
        set -- "$@" "$arg"
        ;;
      --task=*)
        TASKS="${TASKS} ${arg//--task=/}"
        set -- "$@" "$arg"
        ;;
      --ignoreProblems)
        IGNORE_PROBLEMS=true
        ;;
      --ignore_avc_error)
        IGNORE_AVC_ERROR=true
        ;;
      --recipe_option=*)
        echo "Adding arg to Recipe Options: ${arg//--receipe_option=/}"
        ROPTS="${ROPTS} ${arg//--receipe_option=/}"
        ;;
      --kspackage=*)
        echo "Adding arg to Kickstart Packages: ${arg//--kspackage=/}"
        KSPKGS="${KSPKGS} <package name=\\\"${arg//--kspackage=/}\\\"\/>"
        ;;
      --servers=*)
        echo "Servers needed: ${arg//--servers=/}"
        TOTAL_HOSTS=$((TOTAL_HOSTS + ${arg//--servers=/}  ))
        set -- "$@" "$arg"
        ;;
      --clients=*)
        echo "Clients needed: ${arg//--clients=/}"
        TOTAL_HOSTS=$((TOTAL_HOSTS + ${arg//--clients=/} ))
        set -- "$@" "$arg"
        ;;
      *)
        set -- "$@" "$arg"
        ;;
  esac
done

# ensures these are installed
set -- "$@" "--task=/distribution/reservesys"
set -- "$@" "--install=beakerlib"

# debug stuff
if [[ $DEBUGXML == true ]]; then
echo -e "\n==== ARGS ============================================="
cat << DEBUG
args: $@
IGNORE_AVC_ERROR: $IGNORE_AVC_ERROR
IGNORE_PROBLEMS: $IGNORE_PROBLEMS
KSPKGS: $KSPKGS
PASSWORD: $PASSWORD
ROPTS: $ROPTS
TASKS: $TASKS
TIMEOUT: $TIMEOUT
RESERVETIME: $RESERVETIME
TOTAL_HOSTS: $TOTAL_HOSTS
USERNAME: $USERNAME
DEBUG
fi

# do a dryrun through bkr workflow-simple saving the intial xml in file bkrjob.xml
bkr workflow-simple "$@" --dryrun --debug --prettyxml > bkrjob.xml

# all reservations should now be using this job, this requires latest beaker-client
DIST_JOB_FMT="check-install"

# modify the bkrjob.xml with argument values from beakerCheckOut.sh
if [[ $IGNORE_AVC_ERROR == true ]]; then # turn off selinux during install
    # add --taskparam=AVC_ERROR=+no_avc_check  to /distribution/install task
    xmlstarlet ed -L -s "/job/recipeSet/recipe/task[@name='/distribution/$DIST_JOB_FMT']" -t elem -n params -v foobar bkrjob.xml
    sed -i -e 's/foobar/<param name="AVC_ERROR" value="+no_avc_check"\/>/g' bkrjob.xml
fi
if [[ -n $KSPKGS ]]; then                # add --kspackage values
    sed -i -e s/"<\/distroRequires>"/"<\/distroRequires> <packages> $(echo $KSPKGS) <\/packages>"/g bkrjob.xml
fi
if [[ -n $ROPTS ]]; then                 # add --recipe_option values
    sed -i -e s/"<recipe "/"<recipe $(echo $ROPTS) "/g bkrjob.xml
fi
if [[ -n $RESERVETIME ]]; then           # add a --reservetime
    sed -i -E s/"(<task name=\"\/distribution\/reservesys\" role=\"STANDALONE\">)"/"\1 <params> <param name=\"RESERVETIME\" value=\"$(echo $RESERVETIME)\"\/> <\/params>"/g bkrjob.xml
fi
sed -i /"^ *<params\/>"/d bkrjob.xml     # delete lines with empty <params/>
echo -e "\n==== JOB XML =========================================="
xmlstarlet fo bkrjob.xml

# if debugging, show the modified bkrjob.xml and exit
if [[ $DEBUGXML == true ]]; then
    rm bkrjob.xml
    exit 0
fi

# submit bkrjob.xml to beaker
bkr job-submit $USERNAME $PASSWORD bkrjob.xml > job || (rm bkrjob.xml && exit 1)
JOB=`cat job | cut -d \' -f 2`
# had a instance where beaker returned 'bkr.server.bexceptions.BX:u' but the script just continued,
# trying to prevent that in the future - DJ-110415
# check JOB for a valid number following 'j:'
if ! [[ ${JOB:2} =~ ^[0-9]+$ ]] ; then
   echo "error: job (${JOB}) doesn't appear to be valid"; exit 1
fi

echo -e "\n==== JOB DETAILS ======================================"
echo "bkr workflow-simple $@"

echo -e "\n==== JOB ID ==========================================="
cat job # Submitted: ['J:11363484']
echo "https://beaker.engineering.redhat.com/jobs/${JOB:2}"
echo "To cancel: bkr job-cancel $USERNAME $PASSWORD ${JOB}"

echo -e "\n==== PROVISION STATUS ================================="
echo "Timeout: $TIMEOUT minutes"
TIME="0"
PREV_STATUS="Hasn't Started Yet."
PASS_STRING="Pass"
if [[ $TOTAL_HOSTS > 0 ]]; then
    MAX=`expr $TOTAL_HOSTS + 1`
    PASS_STRING=`seq -s "Pass" $MAX | sed 's/[0-9]//g'`
fi
while [ $TIME -lt $TIMEOUT ]; do
  bkr job-results $JOB $USERNAME $PASSWORD > job-result || (echo "Could not create job-result." && exit 1)

  PROVISION_STATUS=$(xmlstarlet sel -t --value-of "//task[@name='/distribution/$DIST_JOB_FMT']/@status" job-result)
  PROVISION_RESULT=$(xmlstarlet sel -t --value-of "//task[@name='/distribution/$DIST_JOB_FMT']/@result" job-result)
  if [[ $PROVISION_RESULT == $PASS_STRING ]]; then
    echo
    echo "Job has completed."
    echo "Provision Status: $PROVISION_STATUS"
    echo "Provision Result: $PROVISION_RESULT"
    break
  elif [[ $PROVISION_STATUS == *Aborted* ]] || [[ $PROVISION_STATUS == *Cancelled* ]]; then
    echo
    echo "Job FAILED!"
    echo "Provision Status: $PROVISION_STATUS"
    echo "Provision Result: $PROVISION_RESULT"
    exit 1
    break
  elif [[ $PROVISION_RESULT != *None* ]] && ([[ $PROVISION_RESULT == *Warn* ]] || [[ $PROVISION_RESULT == *Fail* ]]); then
    echo
    echo "Provision Status: $PROVISION_STATUS"
    echo "Provision Result: $PROVISION_RESULT"
    if [[ $IGNORE_PROBLEMS == true ]]; then
      echo "Job has completed."
      break
    else
      echo "Job FAILED!"
      exit 1
    fi
  elif [[ "$PREV_STATUS" == "$PROVISION_STATUS" ]]; then
    echo -n "."
    TIME=$(expr $TIME + 1)
    sleep 60
  else
   echo
   echo "Provision Status: $PROVISION_STATUS"
   echo "Provision Result: $PROVISION_RESULT"
   date
   PREV_STATUS=$PROVISION_STATUS
   echo "Timeout timer reset."
   TIME="0"
   sleep 60
  fi
done
if [[ $TIME -eq $TIMEOUT ]]; then
  echo "Timeout reached."
  bkr job-cancel $JOB $USERNAME $PASSWORD
  exit 1
fi


JOB_HOSTNAME=""
if [[ $TOTAL_HOSTS > 0 ]]; then
    for i in `seq 1 $TOTAL_HOSTS`; do
        NAME=`xmlstarlet sel -t -v //recipe[$i]/@system job-result`
        if [[ -z $JOB_HOSTNAME ]]; then
            JOB_HOSTNAME="${NAME}"
        else
            JOB_HOSTNAME="${JOB_HOSTNAME}:${NAME}"
        fi
        echo "HOSTNAME = $NAME - https://beaker.engineering.redhat.com/view/$NAME"
    done
else
    JOB_HOSTNAME=`xmlstarlet sel -t -v //recipe/@system job-result`
    echo "HOSTNAME = $JOB_HOSTNAME - https://beaker.engineering.redhat.com/view/$JOB_HOSTNAME"
fi
rm -Rf hostname
echo $JOB_HOSTNAME > hostname

DISTRO=`xmlstarlet sel -t --value-of "//recipe/@distro" job-result`
echo $DISTRO
echo $DISTRO > distro

echo -e "\n==== TASK STATUS ======================================"
for TASK in $TASKS; do
  echo "==== TASK $TASK"
  PREV_STATUS="Hasn't Started Yet."
  while [ true ]; do
    bkr job-results $JOB $USERNAME $PASSWORD > job-result
    TASK_RESULT=$(xmlstarlet sel -t --value-of "//task[@name='$TASK']/@result" job-result)
    TASK_STATUS=$(xmlstarlet sel -t --value-of "//task[@name='$TASK']/@status" job-result)
    if [ $TASK_RESULT == $PASS_STRING ]; then
      echo
      echo "Job has completed."
      echo "Task Status: $TASK_STATUS"
      echo "Task Result: $TASK_RESULT"
      break
    # We could add support for --ignoreProblems but haven't seen any issues installing automatjon-keys, and if
    #   it did fail, you probably shouldn't ignore that one, leaving this alone for now
    elif [[ $TASK_RESULT == "Warn" ]] || [[ $TASK_RESULT == "Fail" ]]; then
      EXIT_RESULT=$(xmlstarlet sel -t --value-of "//task[@name='$TASK']/results/result[@path='rhts_task/exit']/@result" job-result)
      if [[ $EXIT_RESULT == "Pass" ]]; then
        echo
        echo "Job has completed."
        echo "Task Status: $TASK_STATUS"
        echo "Task Result: $EXIT_RESULT"
        break
      else
        echo
        echo "Job FAILED!"
        echo "Task Status: $TASK_STATUS"
        echo "Task Result: $TASK_RESULT"
        bkr job-cancel $JOB $USERNAME $PASSWORD
        exit 1
        break
      fi
    elif [[ "$PREV_STATUS" == "$TASK_STATUS" ]]; then
      echo -n "."
      sleep 60
    else
      echo
      echo "Task Status: $TASK_STATUS"
      echo "Task Result: $TASK_RESULT"
      date
      PREV_STATUS=$TASK_STATUS
      sleep 60
    fi
  done
  echo
done
