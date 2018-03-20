#!/bin/sh
# ver 1.0r1
# r0 - initial working release
# r1 - code has been updated to process filenames in a safer manner and use modified IFS
# r2 - added cron module, reduced # of backups by 1 because numbering starts from 0, removed extra echos

initialize_variables() {
	# REMOVE THE EXPORT!!!
	export RSYNC_PASSWORD="25028696"

	# Executables
	ID=/usr/bin/id;
	ECHO=/bin/echo;
	MOUNT=/bin/mount;
	RM=/bin/rm;
	MV=/bin/mv;
	CP=/bin/cp;
	TOUCH=/bin/touch;
	RSYNC=/usr/bin/rsync;

	# -----------------------------------------------------------------
	# Input parameters and their default values
	# -----------------------------------------------------------------
	# Define how many backups of each interval to keep.
	NoM=4		# Number of monthly backups to keep
	NoW=4		# Number of weekly backups to keep (logical max. is 4 or 5)
	NoD=7		# Number of daily backups to keep (logical max. is 7)
	NoH=4		# Number of hourly backups to keep (logical max. is 24, but can be more if you want e.g. 30 min. backups)

	# CRON start times
	cMoH=0		# Minute of the hour for hourly backup
	cHoD=1		# Hour of daily backup
	cMoD=10		# Minute of daily backup
	cDoW=1		# Day for weekly backup
	cHoW=1		# Hour of weekly backup
	cMoW=20	# Minute of weekly backup
	cDoM=1		# Day of monthly backup
	cHoM=1		# Hour of monthly backup
	cMoM=30		# Minute of monthly backup

	# Variables below -> Although you may assign some defaults here, be careful!
	# Assigning values here may break some logic/safety checks and thus lead to unexpected results.
	# It is recommended to provide values for these parameters via command line options or via config file.

	# Seamingly the same, but used differently throughout the script
	SourceDir=""
	DestDir=""
	InputDir=""
	OutputDir=""

	# Various options or temporary variables
	BackupElements=""
	JobName=""
	cfJobName=""
	Mode=""
	JobRotated=""
	JobDestinations=""
	RsyncPwd=""
	optRelative=""
	optVerbose=""

	# These are different files which can be assigned through parameters
	IncludesFile=""
	ExcludesFile=""
	ConfigFile=""

	Version="1.0 rel. 1"
	tab=$(printf '\t')
	nwln=$(printf '\nX') && nwln=${nwln%X}
}

# ----------------------------
# -----     FUNCTIONS    -----
#-----------------------------

fix_path() {
	# Function sets value of variable, which name is passed as $1.
	# The path being verified is passed as $2

	# Absolute path stays absolute
	# Just a file name or relative path, which begins with '-' is prepended with './'
	# Paths beginning with rsync:// or containing @ character are left intact
	# Function also removes control characters from file names.

	tmpstring="${2}"
	case "${tmpstring}" in
		rsync://*)
			:
			;;
		*@*)
			:
			;;
		/*)
			:
			;;
		-*)
			tmpstring="./${tmpstring}"
			;;
	esac
	# If filename contains control characters, we will reject it for security reasons
	controlchars="$(printf '*[\001-\037\177]*')"
	case "${tmpstring}" in
		${controlchars})
			echo "Illegal [control] characters found in path! (Not showing it for security reasons)."
			tmpstring=""
		;;
	esac
	eval "$1=\${tmpstring}"
}

get_inputs() {
	# Processes inputs (from command line)
	# Parameter specified by input can have 0, 1, or 2 arguments
	# (for future even more, but currently we need 2 only for backup and majority then uses only 1 or none)
	# (if more is needed in future, modify call to "process_input" and pass all remaining parameters)
	# Script processes ALL command line parameters first, and if one of them is config file, then config file is processed afterwards.
	# Command line parameters take precedence over config file definitions!
	# Multiple definitions of same parameter -> first one is considered (exceptions! - see process_input function)
	#
	# Depending on result of process_input (which returns how many arguments it "consumed", we shift the command line parameters accordingly

	while [ $# != 0 ]
	do
		process_input "$1" "$2" "$3"
		NumOfShifts=$?
		while [ $NumOfShifts -gt 0 ]
		do
			shift
			NumOfShifts=$(($NumOfShifts-1))
		done
	done
}


process_input() {
	# $1 - is the parameter name
	# $2, $3 - are parameter values #1 and #2
	#
	# This function is also called when parsing config file (if specified).
	# If parameter has been specified in command line, then if found also in config file, config file value is ignored. (CL overrides CF)
	# Multiple declarations of same parameter are ignored and first declaration is considered.
	# The above is NOT APPLICABLE to parameters where there is no "if" test (e.g. months, weeks, etc.) -> there the last
	# definition takes precedence. This is also logical, as they contain default values.
	# (This is why it is not recommended to specify certain defaults above in variables definitions, because if you do, you basically
	#  can't override them through config file or command line!)
	#
	# Function returns value of how many shifts of original parameters are required (1, 2 or 3; for future could be more)
	#
	# We consider automatic return of 2 after case has been passed. In case of a sinlge argument/switch, return is already
	# within the case option.

	cfg=${3:-}
	case $1 in
		-h|--help)
			show_usage
			exit 0
		;;
		-M|--months)
			# Validate number?
			NoM="$2"
		;;
		-W|--weeks)
			# Validate number?
			NoW="$2"
		;;
		-D|--days)
			# Validate number?
			NoD="$2"
		;;
		-H|--hours)
			# Validate number?
			NoH="$2"
		;;
		# Cron start times related intputs (no check here, because cron will reject anyway)
		--moh)	cMoH="$2" ;;
		--mod)	cMoD="$2" ;;
		--hod)	cHoD="$2" ;;
		--mow)	cMoW="$2" ;;
		--how)	cHoW="$2" ;;
		--dow)	cDoW="$2" ;;
		--mom)	cMoM="$2" ;;
		--hom)	cHoM="$2" ;;
		--dom)	cDoM="$2" ;;
		-i|--input)
			# There can be one and only one input parameter with a matching output parameter. All other definitions will be ignored.
			# For multiple source/dest combinations per job, use the --backup parameter
			# Eventually input and output will become deprecated in favor of --backup.

			# Checks if we already have an inputdir, if not, removes trailing '/' if exists and then checks and fixes the path
			[ -z "$InputDir" ] && [ -z "$InputDir" ] && fix_path InputDir "${2%/}"
		;;
		-o|--output)
			# Dtto as above
			[ -z "$OutputDir" ] && fix_path OutputDir "${2%/}"
			# RSYNC or SSH as destination are not supported!
			check_dest_type "${OutputDir}"
			if [ "${DestType}" = "R" ] || [ "${DestType}" = "S" ]; then
				echo "RSYNC or SSH as destination is NOT SUPPORTED!"
				OutputDir=""
			fi
		;;
		-b|--backup)
			#
			#[ -z "$BackupElements" ] && BackupElements="${2%/};${3%/}" || BackupElements=$(printf "%s;%s;%s" "$BackupElements" "${2%/}" "${3%/}")
			fix_path tmpA "${2%/}"
			fix_path tmpB "${3%/}"
			# RSYNC or SSH as destination are not supported!
			check_dest_type "${tmpB}"
			if [ "${DestType}" = "R" ] || [ "${DestType}" = "S" ]; then
				echo "RSYNC or SSH as destination is NOT SUPPORTED!"
				tmpB=""
			fi
			if [ -z "$BackupElements" ] && [ ! -z "${tmpA}" ] && [ ! -z "${tmpB}" ]; then
				BackupElements="${tmpA}${tab}${tmpB}"
			else
				BackupElements="$BackupElements${nwln}${tmpA}${tab}${tmpB}"
			fi
			unset tmpA
			unset tmpB
			return 3
		;;
		-n|--name)
			# When using config file, job name is assigned from inside [...] and all other possible name definitions in conf file are ignored.
			# Exception to the above is if the --name is used as command line parameter to override the config value.
			[ -z "$JobName" ] && JobName="$2"
		;;
		--includes)
			# If not defined already, then check path for correct characters
			# then check if file exists. If yes, keep it, if not, set var to empty string.
			[ -z "$IncludesFile" ] && fix_path IncludesFile "${2}" \
					&& [ ! -f "${IncludesFile}" ] && IncludesFile=""
		;;
		--excludes)
			# Dtto as above
			[ -z "$ExcludesFile" ] && fix_path ExcludesFile "${2}" \
					&& [ ! -f "${ExcludesFile}" ] && ExcludesFile=""
		;;
		--relative)
			optRelative="--relative"
			return 1
		;;
		-v|--verbose)
			optVerbose="--verbose"
			return 1
		;;
		--rsyncpwd)
			# Check if $2 is path to file. If yes, then set variable to that path and later add to appropriate rsync option.
			# 	If no, then consider it text password and export the variable
			RsyncPwd=""
			if [ -f "${2}" ]; then
				[ -z "$RsyncPwd" ] && fix_path RsyncPwd "${2}"
			else
				export RSYNC_PASSWORD="${2}"
			fi
		;;
		--config)
			# Do not allow to be set if set in a config file! This can only come from command line (in other words, command line is processed first
			# and all other definitions are ignored).
			[ -z "$ConfigFile" ] && fix_path ConfigFile "$2"
			;;
		-m|--mode)
			# Setting mode in config file is ignored! 
			[ -z "$Mode" ] && Mode="$2"
		;;
		M|W|D|H|C)
			# This maybe will become deprecated in favor of the above option
			# (keeping it now for historical compatibility)
			Mode="$1"
			return 1
		;;
		*)
			# Check if we are processing from config file
			if [ "$3" != "conf_file" ]; then
				echo "Uknown parameter '$1'"; echo
				show_usage
				exit 1
			else
				if [ "$2" = "dummy" ]; then
					return 100
				else
					echo "Ignoring unknow configuration parameter in config file:"
					echo "$1 = $2"
				fi
				# In case of config file, we do not abort but try to continue...
				# (why not in case of command line??? -> good question)
			fi
	esac
	return 2	# Default return
}



beginswith() { case $2 in "$1"*) true;; *) false;; esac; }
contains() {
    string="$1"
    substring="$2"
    if test "${string#*$substring}" != "$string"
    then
        return 0    # $substring is in $string
    else
        return 1    # $substring is not in $string
    fi
}


check_dest_type() {
	# This function attempts to determine where is the backup destination:
	#     R -> Rsync daemon host
	#     S -> SSH daemon host
	#     L -> Local directory (can be of course remote, but mounted locally)
	#
	# Not yet used, but probably necessary for checking of input parameters.
	# Also should be made generic to test also input, not just destination.
	if beginswith "${1}" "rsync://"; then
		DestType="R"
	elif contains "${1}" "::"; then
		DestType="R"
	elif contains "${1}" "@"; then
		DestType="S"
	else
		DestType="L"
	fi
}


check_required() {
	# Function checks if we have all required (minimum) parameters for running backup job:
	# Mode=interval
	# BackupElements=at least one combination of Input/Destination
	# JobName=name of the job
	all_ok=""
	Msg="Required parameter missing -"
	[ -z "${Mode}" ] && echo "${Msg} Mode is not specified" && all_ok="no"
	[ -z "${JobName}" ] && echo "${Msg} Job Name is not specified" && all_ok="no"
	[ -z "${BackupElements}" ] && "${Msg} No source/destination backup elements are defined" && all_ok="no"

	[ ! -z "${all_ok}" ] && show_usage && exit 3
}



parse_config_file() {
	# Open config file and go line by line
	# Each line is parsed, and can be empty; # as comment; or *=* as parameter and its value(s)
	# If parameter line, then after split we send it to process_input function

	chFile="${1}"
	[ ! -f "${chFile}" ] && exit 13		# Config file not found... do we exit or continue without it? I think it's safer to exit.

	while IFS= read -r chLine <&3; do
		case "${chLine}" in
			\#*)	# comment line, ignore it
				:
			;;
			\[*\])                           # Job name identifier
				if [ -z "${JobName}" ]; then
					JobName="${chLine}"
					# Now remove brackets []
					JobName="${JobName%]}"
					JobName="${JobName#[}"
				fi
			;;
			?*=*)	
				# Rest should be either empty lines or parameter=value strings
				set -f
				IFS=$(printf '\n\t=')
				set -- $chLine
				chFieldname="$1"
				if [ "${chFieldname}" = "backup" ]; then
					process_input "--${chFieldname}" "${2}" "${3}"
				else
					process_input "--${chFieldname}" "${2}" "conf_file"
				fi
				set +f
				unset IFS
			;;
			*)                           # catch-all, misformed lines
				# check if we maybe have a standalone option (e.g. relative)
				# if retunr value is from "unrecognized option", then print error (and? now we continue, should we exit?)
				process_input "--${chLine}" "dummy" "conf_file"
				if [ "$?" -eq "100" ]; then
					[ ! -z "${chLine}" ] && printf '%s\n%s\n' "Error: cannot decipher in stanza ${cfJobName}, line:" "${chLine}"
				fi
			;;
	     esac
	done 3< "${chFile}"
}

prepare_options() {
	# Function defines standard and optional options for rsync, as specified by parameters in command line or config file
	[ ! "${Mode}" = "C" ] && Options="-a --delete --delete-excluded"
	[ ! -z "${optVerbose}" ] && Options="${Options} ${optVerbose}"
	[ ! -z "${optRelative}" ] && Options="${Options} ${optRelative}"
	[ ! -z "${IncludesFile}" ] && Options="${Options} --includes \"${IncludesFile}\""
	[ ! -z "${ExcludesFile}" ] && Options="${Options} --excludes \"${ExcludesFile}\""
	[ ! -z "${RsyncPwd}" ] && OtherOptions="${OtherOptions} --rsyncpwd ${RsyncPwd}"
}

add_destination_and_check_for_multiple() {
	# $1 - Current destination being processed
	# Check if destination was already used. If yes, and --relative is not applied, issue an warning.
	# (Effect -> only the last backup to the destination will be kept and previous sources will be erased, if --relative not in place)
	contains "${JobDestinations}" "${nwln}${1}${nwln}"
	if [ "$?" -eq "0" ] && [ -z "${optRelative}" ]; then
		printf '%s\n%s' "Warning! Same destination for multiple backup sources within single job found." \
				"This may lead to undesired results!"
	fi
	JobDestinations="${JobDestinations}${nwln}${1}${nwln}"
}
rotate_interval() {
	# Rotates existing backups of given interval
	# $1 -> interval name
	# $2 -> job base
	# $3 -> maximum number of backups in given interval

	riInterval="$1"
	riJobBase="$2"
	riMax="$3"

	j="$riMax"
	while [ "${j}" -ge "0" ];
	do
		DA="${riJobBase}/${riInterval}.${j}"
		#echo "Rotating: $DA with max $j"
		if [ -d "${DA}" ]; then
			i=$(( j + 1 ))
			DB="${riJobBase}/${riInterval}.${i}"
			if [ "${j}" -eq "${riMax}" ]; then
				# Remove oldest snapshot if at $Max
				$RM -rf "${DA}"
			elif [ "${j}" -ge "1" ]; then
				# Shift remaining snapshots, except for the most recent one
				$MV "${DA}" "${DB}"
			else
				# Copy (hard-link) most recent one, so that for new snapshot we have a base to udpate
				$CP -al "${DA}" "${DB}"
			fi
		fi
		j=$(( j - 1 ))
	done
}
perform_backup() {
	# $1 - Source dir; $2 - Destination backup root directory
	SourceDir="$1"
	DestDir="$2"

	add_destination_and_check_for_multiple "${DestDir}"

	case "$Mode" in
		H)
			Max="${NoH}"
			Interval="hourly"
			JobBase="${DestDir}/${JobName}"
			if [ "${JobName}${JobBase}${Interval}" != "${JobRotated}" ]; then
				rotate_interval "${Interval}" "${JobBase}" "${Max}"
				JobRotated="${JobName}${JobBase}${Interval}"
			fi
			unset IFS	# Just to make sure that $Options get parsed correctly
			# create target directory (if exists, nothing is shown)
			$RSYNC /dev/null "${DestDir}/" > /dev/null 2>&1
			$RSYNC /dev/null "${JobBase}/" > /dev/null 2>&1
			# make bakcup
			$RSYNC ${Options} "${SourceDir}" "${JobBase}/${Interval}.0"
			$TOUCH "${JobBase}/${Interval}.0"
		;;
		D|W|M)
			echo "Daily, weekly, monthly"
			# These are essentially copies made with hard-links of the most recent
			# lower level backup (.0)
			if [ "${Mode}" = "M" ]; then
				Max="${NoM}"
				Interval="monthly"
				PrevInt="weekly"
			elif [ "${Mode}" = "W" ]; then
				Max="${NoW}"
				Interval="weekly"
				PrevInt="daily"
			elif [ "${Mode}" = "D" ]; then
				Max="${NoD}"
				Interval="daily"
				PrevInt="hourly"
			fi

			JobBase="${DestDir}/${JobName}"
			rotate_interval "${Interval}" "${JobBase}" "${Max}"
			[ -d "${JobBase}/${PrevInt}.0" ] && $CP -al "${JobBase}/${PrevInt}.0" "${JobBase}/${Interval}.0"
		;;
		C)
			define_cron_jobs
		;;
		*)
			echo "Critical stop. Unknown mode detected > ${Mode}"
			exit 13
	esac
}

backup_loop() {
	# This loops through all identified combinations of source and destination defined within current job.
	#
	# TO DO: (Make a separate function/loop for it) -> Process multiple jobs if defined in config file (but that will be a separate loop either in main part or in separate function


	IFS=$(printf '\n\t')
	Src=""
	for argument in $(echo "$@");
	do
		if [ -z "${Src}" ]; then
			Src="${argument}"
		else
			check_dest_type "${argument}"
			#echo "Backing up >${Src}< into >$argument<"
			if [ "${Mode}" != "C" ]; then
				perform_backup "${Src}" "${argument}"
				#sleep 10
			else
				cBackupElements="${cBackupElements} --backup \"${Src}\" \"${argument}\""
			fi
			Src=""
		fi
	done
	[ "${Mode}" = "C" ] && perform_backup
	unset IFS
}

cmd_line_input_output() {
	if [ ! -z "${InputDir}" ]; then
		if [ -z "${OutputDir}" ]; then
			echo "Backup input specified without output! ...skipping it."
		else
			process_input "--backup" "${InputDir}" "${OutputDir}"
		fi
	else
		if [ ! -z "${OutputDir}" ] && [ -z "${InputDir}" ]; then
			echo "Backup output specified without input! ...skipping it."
		fi
	fi
}

define_cron_jobs() {
# Function takes care of creating/updating cron entries
# Cron entry will be created for each Mode (hourly,daily,weekly,monthly)
# Parameters from config file are "extracted" into command line parameters in cron
# This means that changing config file WILL NOT affect cron jobs.
# User must update(=recreate) cron jobs after changing config file
# Cron jobs are created for current user. Use sudo if another user's crontab should be modified.

	# Detrmine script full path
	prg="$0"
	if [ ! -e "$prg" ]; then
		case $prg in
			(*/*) exit 1;;
			(*) prg=$(command -v -- "$prg") || exit;;
		esac
	fi
	dir=$(cd -P -- "$(dirname -- "$prg")" && pwd -P) || exit
	prg=$dir/$(basename -- "$prg") || exit
	ScriptPath="${prg}"

	HrInt=$((24/${NoH}))

	Options="-M $((NoM+1)) -W $((NoW+1)) -D $((NoD+1)) -H $((NoH+1))"
	# Cron entries
	# IMPORTANT! JobName with quotes must be last parameter before the Mode parameter (used for matching later)
	CjHourly="${cMoH} */${HrInt} * * * ${ScriptPath} ${Options} ${cBackupElements} -n \"${JobName}\" H >/dev/null 2>&1"
	CjDaily="${cMoD} ${cHoD} * * * ${ScriptPath} ${Options} ${cBackupElements} -n \"${JobName}\" D >/dev/null 2>&1"
	CjWeekly="${cMoW} ${cHoW} * * ${cDoW} ${ScriptPath} ${Options} ${cBackupElements} -n \"${JobName}\" W >/dev/null 2>&1"
	CjMonthly="${cMoM} ${cHoM} ${cDoM} * * ${ScriptPath} ${Options} ${cBackupElements} -n \"${JobName}\" M >/dev/null 2>&1"

	# Insert into crontab definitions
	# Remove entry if exists (matching against job name and interval)
	for k in H D W M;
	do
		# Get existing entry line (if exists)
		TA=$(crontab -l | grep "\"${JobName}\" ${k}")
		# And remove it
		(crontab -l ; echo "${TA}") 2>&1 | grep -v "no crontab" | grep -v "\"${JobName}\" ${k}" |  sort | uniq | crontab -
	done
	# Now add new entries
	(crontab -l ; echo "${CjHourly}") 2>&1 | grep -v "no crontab" | sort | uniq | crontab -
	(crontab -l ; echo "${CjDaily}") 2>&1 | grep -v "no crontab" | sort | uniq | crontab -
	(crontab -l ; echo "${CjWeekly}") 2>&1 | grep -v "no crontab" | sort | uniq | crontab -
	(crontab -l ; echo "${CjMonthly}") 2>&1 | grep -v "no crontab" | sort | uniq | crontab -
}

show_usage() {
	echo "$0"
	echo "Version: $Version"
	echo
	echo "Usage:"
cat << ENDOFHELP
rsyncshot is a script for creating rotating backups based on rsync and hard-links. The script utilizes following logic:
There is a "job" defined by job name, which can consist of one or more backups (combination of backup source and backup destination). Each job is then created a rotating backups on hourly, daily, weekly and monthly basis, as defined by respective parameters.

Options to the script can be supplied via command line or via a config file. If you supply config line as well as command line options, the command line overrides the config file on options which are specified in both. Exception to this are input/output directives and "backup" directive, which will be added to the backups specified in config file.

Lastly, the script support creation of cron jobs to run the script in predetermined times automatically.

Usage:
  rsyncshot [options] --input source_path --output dest_path --jobname name [--mode] H|D|W|M|C
  rsyncshot [options] --backup source_path dest_path --jobname name [--mode] H|D|W|M|C
  rsyncshot --config config_file

A job can contain multiple source/destination combinations, but only one can be supplied via input/output directives. Please use --backup directives to specify multiples. The input/output may become deprecated in the future in favor of the --backup.
Mode can be specified with or without the --mode directive. For future it is recommended to use the --mode.

Modes:
  H - hourly   - rotate hourly backups and update the latest hourly backup (hourly.0)
  D - daily   - rotate daily backups and update the latest daily backup to the most recent hourly one (daily.0)
  W - daily   - rotate weekly backups and update the latest weekly backup to the most recent daily one (weekly.0)
  M - daily   - rotate monthly backups and update the latest monthly backup to the most recent weekly one (monthly.0)
  C - define cron schedules and jobs for each - hourly, daily, weekly, monthly

Options:
  -h|--help   - show this help text

  -M|--months #   - How many monthly backups to keep (e.g. -M 3 will keep 3 monthly backups) Default value 3.

  -W|--weeks #   - How many weekly backups to keep (e.g. -W 4 will keep 4 weekly backups); Anything above 4 is not logical, as there it is handled with monthly backups, unless you have specific reason to keep more weekly copies. Default value 5.

  -D|--days #   - How many daily backups to keep (e.g. -D 7 will keep 7 daily backups); Anythin above 7 should be covered by weekly backups, unless you have specifi reason to keep more of daily backups in rotation. Default value 7.

  -H|--hours #   - How many hourly backups to keep (e.g. -H 8 will keep 8 hourly backups). This setting also determines the frequency, i.e. -H 8 will cause the hourly backup to be run every 3 hours (determined as freq=24/8). This is applicable if you use the Cron mode (see below) to setup cron jobs. There is no upper limit here, becaus higher number increases frequency. So although -H 48 may seem illogical (should be handled by daily), it actually means you will get hourly backup every 30 minutes. So you stay within 1 day. Default value 24.

  -n|--name   - name of the job. The name is also used to contruct folder names of backups in the destinantion folder (e.g. dest_name/job_name/hourly.0)

  -b|--backup source_path dest_path
	- will instruct rsync to create a snapshot of the source_path into the dest_path. There can be multiple --backup directivies per job.
	- The source_path can be either: (1) a local path; (2) an rsyncd path determined by rsync://user@computer:volume/path or user@computer::volume/path; or (3) and ssh path determined by ssh://user@computer:/path.
	- The dest_path can only be a local path, as there is no easy way to create rotating backups on remote ends using rsync or ssh protocol.

  -i|--input source_path
	- specify a source path for the job. Same variants apply as for --backup.
	- There can be only one source_path specified via --input directive per job. If you want multiple inputs, then use the --backup directive instead.
	- Used for backwards compatibility. This option may become deprecated in the future versions. It is strongly recommended to use the --backup directive instead.

  -o|--output dest_path
	- specify destination target for given input path. Same limits apply as in --backup.
	- There can be only one dest_path specified via --output directive per job. If you want multiple output definitions, then use the --backup directive instead.
	- Used for backwards compatibility. This option may become deprecated in the future versions. It is strongly recommended to use the --backup directive instead.
  Input and Output complement each other. One cannot be used without specifying the other one.

  --includes file	- specifies the "includes" file used by rsync. For details about includes file refer to rsync documentation.

  --excludes file	- specifies the "excludes" file used by rsync. For details about excludes file refer to rsync documentation.

  --relative		- use the "relative" option for rsync. This is useful if you are backing up multiple sources into the same destination.

  -v|--verbose	- Use the verbose option of rsync. Not recommended if you plan to run your jobs from cron.

  --rsyncpwd [file|password]	- password to use when connecting to rsync daemon. Two alternatives exist here:
		(1) if you specify a path to a file and that file exists, then it is treated as the 'secrets' file, which contains the password;
		(2) if specified parameter is not a file, then password is exported as RSYNC_PASSWORD environment variable. Please note, that on some systems this may be a security vulnerability, if the system shows exported variables system wide.

  --config path_to_file - specifies a path to a file which contains configuration information. The file can contain same options as command line in format specified below. Please note, that the command line parameters (except for input/output/backup) override options specififed in the config file.
	Config file format:
		[JobName]
		backup=/source/dir /dest/dir
		backup=/another/source /another/dest
		hourly=10
		dialy=5
		relative
	As you can see, parameters are specified without the "--" and if they require value, value is assigned using "=".
	Using config file from command line to run a hourly backup can be as easy as: rsyncshot --config /home/user/my_config H
	You may also use the config file to create cron jobs: rsyncshot --config /home/user/my_config C
	However, in that case the parameters will be expanded for the cron job execution line. In other words, after you use config file to create a cron jobs, modifying the config file will not have an effect on the cron jobs. You will have to update the cron jobs by running the "C" mode again.

Cron start times related parameters:
(all these take as a parameter format required by cron (usually number). Wrong value will be rejected by cron.)
  --moh	- Minute Of the Hour for when to run hourly jobs. --moh 0 means run at full hour. --moh 15 runs 15 minutes past the hour

  --mod	- Minute of Daily -> minutes when to to run the daily backup job.

  --hod	- Hour of daily backup -> at which hour to run daily backup. Example: --hod 4 --mod 10 runs daily backup at 4:10 am

  --mow	- Minute of weekly backup -> same as above, but for weekly backup.

  --how	- Hour of daily backup -> same as above, but for weekly backup.

  --dow	- Day of weekly backup -> specify a day on which to run weekly backup.

  --mom	- Minute of monthly -> same as above

  --hom	- Hour of monthly -> same as above

  --dom	- Day of month when to run monthly backups

Examples:
	Run hourly backup for source_dir to dest_dir using default values:
	rsyncshot --backup source_dir dest_dir --name test_job --mode H

	Run weekly backup using verbose mode for rsyncd source:
	rsyncshot --backup rsync://username@userspc_or_ip.local.net:volume_name/directory /local_backup_destination --rsyncpwd /etc/rss.secrets --name test_job2 --mode W

	Run a daily backup based on config file configuration, overriding --relative option and adding another source/dest combination:
	rsyncshot --config /etc/job_name.config --relative --input /extra/source --output /extra/destinatnion --mode D
	(note --name is not required as it is taken from config file)

	Create cron jobs for hourly,daily,weekly (specified) and monthly (use default) runs based on provided parameters:
	rsyncshot -H 12 -D 5 -W 2 --backup /home/user/important /safe/dest/folder --name my_important_job C
ENDOFHELP
}
# -------------------------------------------
# -----     MAIN SCRIPT STARTS BELOW    -----
#--------------------------------------------

oldSetOptions=$(set +o)
set -f
set -x

initialize_variables
get_inputs "$@"

# Reduce # of wanted backups by 1, as we start numbering from 0
# If negative is given, make it 0 (i.e. 1 backup)
	[ "${NoM}" -gt "0" ] && NoM=$((NoM-1)) || NoM=0
	[ "${NoW}" -gt "0" ] && NoW=$((NoW-1)) || NoW=0
	[ "${NoD}" -gt "0" ] && NoD=$((NoD-1)) || NoD=0
	[ "${NoH}" -gt "0" ] && NoH=$((NoH-1)) || NoH=0

# Do we have a config file? Parse it if yes.
[ ! -z "${ConfigFile}" ] && parse_config_file "${ConfigFile}"

# Add input and output parameters to backup elements, if they were defined
cmd_line_input_output

check_required
prepare_options

# Start the backup
backup_loop "${BackupElements}"

# Restore everything back to original settings
unset IFS
eval "$oldSetOptions" 2> /dev/null
