#!/bin/bash

CFGFILE="/etc/ostree/isula-ostree.cfg"
LOGFILE="/var/log/isula-ostree.log"

Usage()
{
        cat << EOF
Usage: `basename $0` [OPTION...] COMMAND
Commands:
  upgrade		Perform OS upgrade operation
  rollback		Perform OS rollback operation
  status		Check available OS versions
  log			Check upgrade/rollback logs
  reboot		Perform OS reboot operation

Help Options:
  -h, --help		Display help messages
EOF
}

GetCurVersion()
{
	echo`rpm-ostree status | grep -A 2 â | grep Version | cut -d ":" -f 2-6`
}
GetBackupVersion()
{
        echo`rpm-ostree status | grep -A 4 Deployments | grep Version | cut -d ":" -f 2-6`
}

Upgrade()
{
        Result="Fail"
        CurVersion=$(GetCurVersion)
	echo "LASTTIME=$(date +"%Y-%m-%d %H:%M:%S")" > $CFGFILE
	echo "LASTSEQ=0" >> $CFGFILE
	seq=1
	rpm-ostree upgrade 2>&1 | while read line
	do
		echo $line | sed -u "s/^/time: $(date +"%Y-%m-%d %H:%M:%S"); seq: $seq; msg: Upgrade log: &/g" >> $LOGFILE
		seq=`expr $seq + 1`
	done
        if [ $? != 0 ]; then
        	echo "time: $(date +"%Y-%m-%d %H:%M:%S"); seq: $seq; msg: cmd exec error: rpm-ostree upgrade" >> $LOGFILE
        elif [ "`tail -1 $LOGFILE | grep 'reboot'`" != "" ]; then
                Result="Success"
        fi
        NextVersion=$(GetBackupVersion)
        cat << EOF
        Name : Ostree,
        CurVersion : $CurVersion,
        NextVersion : $NextVersion,
        Result : $Result
EOF

	if [ $Result == "Fail" ]; then
		exit 1
	fi
}

Rollback()
{
        Result="Fail"
        CurVersion=$(GetCurVersion)
	echo "LASTTIME=$(date +"%Y-%m-%d %H:%M:%S")" > $CFGFILE
	echo "LASTSEQ=0" >> $CFGFILE
	seq=1
	rpm-ostree rollback 2>&1 | while read line
	do
		echo $line | sed -u "s/^/time: $(date +"%Y-%m-%d %H:%M:%S"); seq: $seq; msg: Rollback log: &/g" >> $LOGFILE
		seq=`expr $seq + 1`
	done
        if [ $? != 0 ]; then
        	echo "time: $(date +"%Y-%m-%d %H:%M:%S"); seq: $seq; msg: cmd exec error: rpm-ostree rollback;" >> $LOGFILE
        elif [ "`tail -1 $LOGFILE | grep 'reboot'`" != "" ]; then
                Result="Success"
        fi
        NextVersion=$(GetBackupVersion)
        cat << EOF
        Name : Ostree,
        CurVersion : $CurVersion,
        NextVersion : $NextVersion,
        Result : $Result
EOF

	if [ $Result == "Fail" ]; then
		exit 1
	fi
}

Status()
{
        CurVersion=$(GetCurVersion)
        VersionCount=`rpm-ostree status | grep -c Version`
        if [ "$VersionCount" = "1" ]; then
                BackupVersion="Idle"
        else
                BackupVersion=`rpm-ostree status |grep " Version" | cut -d ":" -f 2-6 | sed "/$CurVersion/d"`
        fi
        cat << EOF
        Name : Ostree,
        CurVersion : $CurVersion,
        BackupVersion : $BackupVersion,
        Result : Success
EOF
}

Log()
{
	if [ ! -f $CFGFILE -o ! -f $LOGFILE ]; then
		echo "No upgrade or rollback operation yet"
		exit 0
	fi

	LASTTIME=`sed '/^LASTTIME=/!d;s/.*=//' $CFGFILE`
	if [ -z "$LASTTIME" ]; then
		echo "Empty ostree upgrade/rollback log file"
		exit 0
	fi

	LASTSEQ=`sed '/^LASTSEQ=/!d;s/.*=//' $CFGFILE`
	nowprogress="0%"
	while read line;
        do
            if [ "$line" = "" ]; then
                continue
	    fi
		# Filter any old-format logs
		if [ "`echo $line | grep seq:`" == "" ]; then
			continue
		fi

            TIME=`echo $line | sed 's/time: //;s/;.*$//'`
            SEQ=`echo $line | cut -f 2 -d ";" | sed 's/seq: //'`
	    if [ `date -d "$TIME" +%s` -ge `date -d "$LASTTIME" +%s` -a $SEQ -gt $LASTSEQ ]; then
		if [[ $line == *"Moving "* ]]; then
			nowprogress="5%"
		elif [[ $line == *"Updating from"* ]]; then
			nowprogress="5%"
		elif [[ $line =~ "Scanning metadata" ]]; then
			nowprogress="10%"
		elif [[ $line =~ "Copying " ]]; then
			nowprogress="70%"
		elif [[ $line =~ "Transaction complete" ]]; then
			nowprogress="90%"
		elif [[ $line =~ "systemctl reboot" ]]; then
			nowprogress="100%"
		elif [[ $line =~ "No upgrade available" ]]; then
			nowprogress="100%"
		elif [[ $line =~ "openat: No such file or directory" ]]; then
			nowprogress="100%"
		fi
		echo "$line; Progress: $nowprogress"

		echo "LASTTIME=$(date -d "$TIME" +"%Y-%m-%d %H:%M:%S")" > $CFGFILE
		echo "LASTSEQ=$SEQ" >> $CFGFILE
            fi
        done < $LOGFILE
}

Reboot()
{
        cat << EOF
        Name : Ostree,
        Message : Good Luck AND bye,
        Status : Done
EOF
        echo "time: $(date +"%Y-%m-%d %H:%M:%S"); seq: 1; msg: Reboot log: rebooting;" >> $LOGFILE
        systemctl reboot
        if [ $? != 0 ]; then
                echo "time: $(date +"%Y-%m-%d %H:%M:%S"); seq: 1; msg: cmd exec error: systemctl reboot" >> $LOGFILE
        fi
}

if [ $# != 1 ]; then
	Usage
	exit 1
fi

case $1 in
        upgrade) Upgrade; exit 0;;
        rollback) Rollback; exit 0;;
        status) Status; exit 0;;
        log) Log; exit 0;;
        reboot) Reboot; exit 0;;
	-h) Usage; exit 0;;
	--help) Usage; exit 0;;
        *) Usage; echo "Unknown Command $1."; exit 1;;
esac
