#!/bin/sh

lastLogfile="/var/log/backup-last.log"
lastMailLogfile="/var/log/mail-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/backup-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

sendEmail() {
  if [ -n "${MAILX_ARGS}" ]; then
      sh -c "mailx -v -S sendwait -s $1 ${MAILX_ARGS} < ${lastLogfile} > ${lastMailLogfile} 2>&1"
      if [ $? == 0 ]; then
          echo "Mail notification successfully sent."
      else
          echo "Sending mail notification FAILED. Check ${lastMailLogfile} for further information."
      fi
  fi
}

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Backup at $(date)" >> ${lastLogfile}
logLast "BACKUP_CRON: ${BACKUP_CRON}"
logLast "RESTIC_TAG: ${RESTIC_TAG}"
logLast "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
logLast "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
logLast "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"

# Make sure only one backup is running at the same time
exec 9>/var/lock/backup.lock || exit 1
flock -n 9 || { logLast  "Backup is already running. Terminating."; sendEmail "'Restic backup already in progress'"; exit 1; }

# Do not save full backup log to logfile but to backup-last.log
restic backup /data ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> ${lastLogfile} 2>&1
rc=$?
logLast "Finished backup at $(date)"
if [[ $rc == 0 ]]; then
    echo "Backup Successfull" 
else
    echo "Backup Failed with Status ${rc}"
    restic unlock
    copyErrorLog
    kill 1
fi

if [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS} >> ${lastLogfile} 2>&1
    rc=$?
    logLast "Finished forget at $(date)"
    if [[ $rc == 0 ]]; then
        echo "Forget Successfull"
    else
        echo "Forget Failed with Status ${rc}"
        restic unlock
        copyErrorLog
    fi
fi

end=`date +%s`
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

sendEmail "'Result of the last restic backup run'"
