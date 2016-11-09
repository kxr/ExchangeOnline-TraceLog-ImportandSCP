#!/bin/bash

# This script should triggered from the cron every minute or so

# It expects Microsoft Office 365 trace logs,
# which are in reverse order i.e newest first and oldest last.
# We are also expecting over lap of log entries between every new log file and the last processed log file.
# So when a log file is fed into the logger, last delivered log line is saved for reference,
# When we recieve a new log file, we seek through the file up to the last reference point,
# and feed the newer logs to the logger and update the last delivered log line reference.
# This is done to make sure we don't miss any logs and we don't add duplicate logs,
# since the logs are collected from a powershell script,
# wich has chances of either missing logs or getting duplicate logs in between intervals.
# So for example we call ever hour to collect logs for the last two hours
# and this script takes care of avoiding duplicate log entries.
# Also, the first line is expected to be the csv header line which will be ignored.

INPUT_DIR="/home/o365logs/input/"
LOGSTASH_DIR="/var/log/office365/trace/"
LOGSTASH_DIR="/tmp/"
PROCESSED_DIR="/home/o365logs/processed/"
LAST_DELIVERED_LOG_REF="/home/o365logs/last_delivered_log_reference"
PROCESSING_LOG="/home/o365logs/log"
TIMESTAMP="$(date +%Y%m%d%H%M%S-%N)"

log() {
        echo "$(date) $1" >> $PROCESSING_LOG
        #echo "$(date) $1"
}


# Start processing files from the input directory,
# Oldest first
find $INPUT_DIR -type f -print0 | xargs -0 ls -tr | while read file
do
        log "INFO: TIMESTAMP=$TIMESTAMP"
        log "INFO: Processing $file"
        #Lets get the first and the last timestamp
        LOG_START_TIME="$(sed -n '2p' $file | cut -d'"' -f2)"
        LOG_START_TS=$(date -d "$LOG_START_TIME" +%s)
        log "INFO: LOG_START_TIME=$LOG_START_TIME ($LOG_START_TS)"
        LOG_END_TIME="$(sed -n '$p' $file | cut -d'"' -f2)"
        LOG_END_TS=$(date -d "$LOG_END_TIME" +%s)
        log "INFO: LOG_END_TIME=$LOG_END_TIME ($LOG_END_TS)"
        LAST_DELIVERED_LOG_TIME="$(sed -n '1p' $LAST_DELIVERED_LOG_REF)"
        LAST_DELIVERED_LOG_TS=$(date -d "$LAST_DELIVERED_LOG_TIME" +%s)
        log "INFO: LAST_DELIVERED_LOG_TIME=$LAST_DELIVERED_LOG_TIME ($LAST_DELIVERED_LOG_TS)"

        # Since we are expecting overlap in the current log file and in the last delivered reference,
        # For the logs to be continuous without missing any thing in between,
        # LOG_END_TIME <  LAST_DELIVERED_LOG_TIME
        # i.e the oldest log in thie file should be less than the last delivered log that was fed to the logger
        #
        # TIME            -------------------------------------------------------------> 
        # LAST LOG     ...-------------------------------L
        # NEW LOG FILE                E----------------------------------S
        if [ "$LOG_START_TS" -le "$LAST_DELIVERED_LOG_TS" ]
        then
                log "ERROR: It seems, we have already processed this log file"
                log "ERROR: $LOG_START_TIME ($LOG_START_TS) is less than or equal to $LAST_DELIVERED_LOG_TIME ($LAST_DELIVERED_LOG_TS)"
                log "ERROR: Ingoring the file"
                mv "$file" "$PROCESSED_DIR/$(basename $file)-AlreadyProcessed-$TIMESTAMP.csv"
        elif [ "$LOG_END_TS" -lt "$LAST_DELIVERED_LOG_TS" ]
        then
                # Also double check that our last delivered log line reference is in this new file
                LAST_DELIVERED_LOG_SENDER="$(sed -n '2p' $LAST_DELIVERED_LOG_REF)"
                LAST_DELIVERED_LOG_RECIPIENT="$(sed -n '3p' $LAST_DELIVERED_LOG_REF)"
                LAST_DELIVERED_LOG_MSGID="$(sed -n '4p' $LAST_DELIVERED_LOG_REF)"
                LAST_DELIVERED_LOG_MTRACEID="$(sed -n '5p' $LAST_DELIVERED_LOG_REF)"
                grep -q -s -i "$LAST_DELIVERED_LOG_SENDER.*$LAST_DELIVERED_LOG_RECIPIENT.*$LAST_DELIVERED_LOG_MTRACEID" $file $> /dev/null
                RETVAL=$?
                if [ "$RETVAL" -eq "0" ]
                then
                        # Output log lines newer than the LAST_DELIVERED_LOG_REF to a new file
                        # 1d will remove the first line which is csv header and pass 2nd line onwards
                        # and next /PATTERN/Q will output lines from the 2nd line up till the pattern match,
                        # pattern line will not be included (thanks to Q).
                        sed "1d;/$LAST_DELIVERED_LOG_SENDER.*$LAST_DELIVERED_LOG_RECIPIENT.*$LAST_DELIVERED_LOG_MTRACEID/IQ" "$file" > "$PROCESSED_DIR/$(basename $file)-newlogs-$TIMESTAMP.csv"
                        # And copy it to the logstash directory for input to elasticsearch
                        cp "$PROCESSED_DIR/$(basename $file)-newlogs-$TIMESTAMP.csv" "$LOGSTASH_DIR"
                        # Update the reference file with the lastest "Delivered" log entry in the new file
                        NEWREF=$(grep -m1 ',"Delivered",' "$PROCESSED_DIR/$(basename $file)-newlogs-$TIMESTAMP.csv")
                        if [ -n "$NEWREF" ] 
                        then
                                mv "$LAST_DELIVERED_LOG_REF" "$PROCESSED_DIR/ldlr.$TIMESTAMP"
                                NEW_REF_DATE=$(echo $NEWREF | cut -d',' -f1 | sed 's/^"//;s/"$//;')
                                NEW_REF_SENDER=$(echo $NEWREF | cut -d',' -f2 | sed 's/^"//;s/"$//;')
                                NEW_REF_RECIPIENT=$(echo $NEWREF | cut -d',' -f3 | sed 's/^"//;s/"$//;')
                                NEW_REF_MSGID=$(echo $NEWREF | cut -d',' -f8 | sed 's/^"//;s/"$//;')
                                NEW_REF_MTRACEID=$(echo $NEWREF | cut -d',' -f9 | sed 's/^"//;s/"$//;')
                                echo -e "$NEW_REF_DATE\n$NEW_REF_SENDER\n$NEW_REF_RECIPIENT\n$NEW_REF_MSGID\n$NEW_REF_MTRACEID" > "$LAST_DELIVERED_LOG_REF"
                                log "INFO: NEW_REF_DATE=$NEW_REF_DATE"
                                log "INFO: NEW_REF_SENDER=$NEW_REF_SENDER"
                                log "INFO: NEW_REF_RECIPIENT=$NEW_REF_RECIPIENT"
                                log "INFO: NEW_REF_MSGID=$NEW_REF_MSGID"
                                log "INFO: NEW_REF_MTRACEID=$NEW_REF_MTRACEID"
                        else
                                log "WARNING: There was no new delivered logs, LAST_DELIVERED_LOG_REF not updated"
                                mv "$file" "$PROCESSED_DIR/$(basename $file)-NoNewDeliveredLogs-$TIMESTAMP.csv"

                        fi
                        # Print out the report
                        log "REPORT: INPUT FILE was $file with $(wc -l $file) lines"
                        log "REPORT: INPUT FILE LOG_START_TIME=$LOG_START_TIME ($LOG_START_TS)"
                        log "REPORT: INPUT FILE LOG_END_TIME=$LOG_END_TIME ($LOG_END_TS)"
                        log "REPORT: LAST_DELIVERED_LOG_TIME=$LAST_DELIVERED_LOG_TIME ($LAST_DELIVERED_LOG_TS)"
                        log "REPORT: NEW LOGS EXTRACTED AFTER LAST_DELIVERED_LOG_TIME = $(wc -l "$PROCESSED_DIR/$(basename $file)-newlogs-$TIMESTAMP.csv")"
                        log "REPORT: NEW LAST_DELIVERED_LOG_REF=$(cat $LAST_DELIVERED_LOG_REF)"
                        # Move the original file to processed
                        mv "$file" "$PROCESSED_DIR/$(basename $file)-orig-$TIMESTAMP.csv"

                else
                        # This should never happen
                        log "ERROR: Although $LOG_END_TS was less than $LAST_DELIVERED_LOG_TS but I couldn't find the last delivered log line in the new file"
                        log "ERROR: LAST_DELIVERED_LOG_REF=$(cat $LAST_DELIVERED_LOG_REF)"
                        mv "$file" "$PROCESSED_DIR/$(basename $file)-RefNotFound-$TIMESTAMP.csv"
                fi
        else
                log "ERROR: No over lap detected. $LOG_END_TIME ($LOG_END_TS) is not less than $LAST_DELIVERED_LOG_TIME ($LAST_DELIVERED_LOG_TS)"
        fi

done

log "###########################################################################"
log "###########################################################################"
log "###########################################################################"
