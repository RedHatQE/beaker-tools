#!/bin/bash
# Copyright (c) 2010 Red Hat, Inc.
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
"This script will reserve a beaker box using bkr workflow-simple.

Available options are:
  --help                                     Prints this message and then exits
  --timeout=TIMEOUT                          The timeout in minutes to wait for a beaker box (default: 180)
  --kspackage=PACKAGE or @GROUP or -@GROUP   Package or group to include/exclude during the kickstart
  --recipe_option=RECIPE_OPTION              Adds RECIPE_OPTION to the <recipe> section
  --ks_meta=KS_META                          Adds KS_META to the kickstart metadata
  --debugxml                                 Preforms a dryrun and prints out the job xml

The following options are avalable to bkr workflow-simple:"
$(bkr workflow-simple --help | tail -n +3 | grep -v "\-\-help")

USAGETEXT
}

TIMEOUT="180"
USERNAME=""
PASSWORD=""
ARCH=""
FAMILY=""
TASKS=""
ROPTS=""
KSMETA=""
KSPKGS=""
OTHERARGS=""
DEBUGXML=false
TOTAL_HOSTS=0
IGNORE_PROBLEMS=false

for i in "$@"
  do
  case $i in
      --help)
         usage
         exit 0
         ;;
      --debugxml)
         DEBUGXML=true
         ;;
      --timeout=*)
         TIMEOUT=$(echo $i | sed -e s/--timeout=//g)
         ;;
      --username=*)
         echo "Setting Arg: $i"
         USERNAME=$i
         ;;
      --password=*)
         echo "Setting Password."
         PASSWORD=$i
         ;;
      --arch=*)
         echo "Setting Arg: $i"
         ARCH=$i
         ;;
      --family=*)
        echo "Setting Arg: $i"
        FAMILY=$i
         ;;
      --task=*)
        echo "Adding arg to tasks: $i"
        TASKS=${TASKS}" "$i
        ;;
      --recipe_option=*)
        echo "Adding arg to Recipe Options: $(echo $i | sed -e s/--recipe_option=//g)"
        ROPTS=${ROPTS}" "$(echo $i |sed -e s/--recipe_option=//g)
        ;;
      --ks_meta=*)
        echo "Adding arg to ks_meta: $(echo $i | sed -e s/--ks_meta=//g)"
        KSMETA=${KSMETA}" "$(echo $i |sed -e s/--ks_meta=//g)
        ;;
      --kspackage=*)
        echo "Adding arg to Kickstart Packages: $(echo $i | sed -e s/--kspackage=//g)"
        KSPKGS=${KSPKGS}" <package name=\\\"$(echo $i | sed -e s/--kspackage=//g)\\\"\/>"
        ;;
      --servers=*)
        echo "Servers needed: $(echo $i | sed -e s/--servers=//g)"
        TOTAL_HOSTS=$(($TOTAL_HOSTS + $(echo $i | sed -e s/--servers=//g)  ))
        OTHERARGS=${OTHERARGS}" "$i
        ;;
      --clients=*)
        echo "Clients needed: $(echo $i | sed -e s/--clients=//g)"
        TOTAL_HOSTS=$(($TOTAL_HOSTS + $(echo $i | sed -e s/--clients=//g) ))
        OTHERARGS=${OTHERARGS}" "$i
        ;;
      --ignoreProblems)
         IGNORE_PROBLEMS=true
        ;;
      *)
        echo "Adding $i to other bkr workflow-simple args."
        OTHERARGS=${OTHERARGS}" "$i
        ;;
  esac
done

#debug stuff
#echo "args: $@"
#echo "USERNAME: $USERNAME"
#echo "PASSWORD: $PASSWORD"
#echo "ARCH: $ARCH"
#echo "FAMILY: $FAMILY"
#echo "TASKS: $TASKS"
#echo "KSPKGS: $KSPKGS"
#echo "OTHERARGS: $OTHERARGS"
#echo "TIMEOUT: $TIMEOUT"
#echo "TOTAL_HOSTS: $TOTAL_HOSTS"

if [[ -z $USERNAME ]] || [[ -z $PASSWORD ]] || [[ -z $ARCH ]] || [[ -z $FAMILY ]] || [[ -z $TASKS ]]  ; then
  echo "bkr workflow-simple requires that a username, password, arch, family, and task be given."
  echo
  usage
  exit 1
fi

if [[ "$ARCH" == "--arch=aarch64" ]]; then
  bkr workflow-simple $USERNAME $PASSWORD $ARCH $FAMILY $TASKS --task=/distribution/reservesys $OTHERARGS --hostrequire="<hostname op='like' value='%hp-moonshot-%'/>" --dryrun --debug --prettyxml > bkrjob.xml
else
  bkr workflow-simple $USERNAME $PASSWORD $ARCH $FAMILY $TASKS --task=/distribution/reservesys $OTHERARGS --dryrun --debug --prettyxml > bkrjob.xml
fi

## adding host requires so we don't screw over the kernel team
sed -i -e '/<hostRequires>/{n;d}' bkrjob.xml
#sed -i -e 's/<hostRequires>/<hostRequires> <and> <cpu_count op="\&gt;=" value="1"\/> <\/and> <system_type value="Machine"\/>/g' bkrjob.xml
if [[ $OTHERARGS == *--keyvalue* ]] || [[ $OTHERARGS == *--machine* ]] || [[ "$ARCH" == "--arch=aarch64" ]]; then
  sed -i -e 's/<hostRequires>/<hostRequires> <and> <system_type value="Machine"\/> <cpu_count op="\&gt;=" value="1"\/>/g' bkrjob.xml
else
  sed -i -e 's/<hostRequires>/<hostRequires> <and> <system_type value="Machine"\/> <cpu_count op="\&gt;=" value="1"\/> <\/and>/g' bkrjob.xml
fi

if [[ -z $KSPKGS ]] && [[ -z $ROPTS ]] && [[ -z $KSMETA ]]; then
  cat bkrjob.xml
  if [[ $DEBUGXML == false ]]; then
    bkr workflow-simple $USERNAME $PASSWORD $ARCH $FAMILY $TASKS --task=/distribution/reservesys $OTHERARGS > job || (echo "bkr workflow-simple $USERNAME --password=***** $ARCH $FAMILY $TASK --task=/distribution/reservesys $OTHERARGS " && cat job && rm bkrjob.xml && exit 1)
  fi
else
  if [[ -n $KSPKGS ]]; then
    sed -i -e s/"<\/distroRequires>"/"<\/distroRequires> <packages> $(echo $KSPKGS) <\/packages>"/g bkrjob.xml
  fi
  if [[ -n $KSMETA ]]; then
    sed -i -e s/"\(ks_meta=\"[method=]*[a-zA-Z]*\)"/"\1 $(echo $KSMETA)"/g bkrjob.xml
  fi
  if [[ -n $ROPTS ]]; then
    sed -i -e s/"<recipe "/"<recipe $(echo $ROPTS) "/g bkrjob.xml
  fi
  cat bkrjob.xml
  if [[ $DEBUGXML == false ]]; then
    bkr job-submit $USERNAME $PASSWORD bkrjob.xml > job || (rm bkrjob.xml && exit 1)
  fi
fi

rm bkrjob.xml

if [[ $DEBUGXML == true ]]; then
  exit 0
fi

echo "===================== JOB DETAILS ================"
echo "bkr workflow-simple $USERNAME --password=***** $ARCH $FAMILY $TASKS --task=/distribution/reservesys $OTHERARGS"
cat job
echo "===================== JOB DETAILS ================"
JOB=`cat job | cut -d \' -f 2`

echo "===================== JOB ID ================"
echo "${JOB} - https://beaker.engineering.redhat.com/jobs/${JOB:2}"
echo "===================== JOB ID ================"

# had a instance where beaker returned 'bkr.server.bexceptions.BX:u' but the script just continued, trying to prevent that in the future - DJ-110415
# now checking for a valid number after dropping 'j:'
if ! [[ ${JOB:2} =~ ^[0-9]+$ ]] ; then
   echo "error: job (${JOB}) doesn't appear to be valid"; exit 1
fi

PASS_STRING="Pass"
if [[ $TOTAL_HOSTS > 0 ]]; then
    MAX=`expr $TOTAL_HOSTS + 1`
    PASS_STRING=`seq -s "Pass" $MAX | sed 's/[0-9]//g'`
fi

echo "===================== PROVISION STATUS ================"
echo "Timeout: $TIMEOUT minutes"
PREV_STATUS="Hasn't Started Yet."
TIME="0"
while [ $TIME -lt $TIMEOUT ]; do
  bkr job-results $JOB $USERNAME $PASSWORD > job-result || (echo "Could not create job-result." && exit 1)
  PROVISION_STATUS=$(xmlstarlet sel -t --value-of "//task[@name='/distribution/install']/@status" job-result)
  PROVISION_RESULT=$(xmlstarlet sel -t --value-of "//task[@name='/distribution/install']/@result" job-result)
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
echo "===================== PROVISION STATUS ================"


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

TASKS=$(echo $TASKS | sed -e s/--task=//g)
for TASK in $TASKS; do
  echo "===================== $TASK STATUS ================"
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
  echo "===================== $TASK STATUS ================"
done
