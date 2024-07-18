param ([switch] $Debug)
$CMK_VERSION = "2.4.0b1"
## VEEAM Backups
## This powershell script needs to be run with the 64bit powershell
## and thus from a 64bit check_mk agent
## If a 64 bit check_mk agent is available it just needs to be renamed with
## the extension .ps1
## If only a 32bit  check_mk agent is available it needs to be relocated to a
## directory given in veeam_backup_status.bat and the .bat file needs to be
## started by the check_mk agent instead.

$pshost = Get-Host
$pswindow = $pshost.ui.rawui

$newsize = $pswindow.buffersize
$newsize.height = 300
$newsize.width = 150
$pswindow.buffersize = $newsize

# Get Information from veeam backup and replication in cmk-friendly format
# V0.9

# Load Veeam Backup and Replication Powershell Snapin
try {
	Import-Module Veeam.Backup.PowerShell -ErrorAction Stop -DisableNameChecking
}
catch {
	try {
		Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop
	}
	catch {
		if ($Debug) { Write-Host "No Veeam powershell modules could be loaded" }
		Exit 1
	}
}


try {
	#####################################
	## Tape Job
	#####################################
	$tapeJobs = Get-VBRTapeJob -WarningAction SilentlyContinue | Where-Object { $_.ScheduleOptions.Enabled }
	Write-Host "<<<veeam_tapejobs:sep(124)>>>"
	Write-Host "JobName|JobID|LastResult|LastState"
	foreach ($tapeJob in $tapeJobs) {
		$jobName = $tapeJob.Name
		$jobID = $tapeJob.Id

		$sessions = @(Get-VBRTapeBackupSession -Job $tapeJob | Sort-Object CreationTime -Descending)
		$lastFinischedSession = $sessions | Where-Object { $_.Progress -ge 100 } | Select-Object -First 1

		$scheduleType = [string]$tapeJob.ScheduleOptions.Type
		if ($null -ne $lastFinischedSession -and $scheduleType -eq "AfterNewBackup") {
			$lastResult = $lastFinischedSession.Result
			$lastState = $lastFinischedSession.State
		}
		else {
			$lastResult = $tapeJob.LastResult
			$lastState = $tapeJob.LastState
		}
		
		Write-Host "$jobName|$jobID|$lastResult|$lastState"
	}

	#####################################
	## CDP Job
	#####################################
	try {
		$cdpjobs = Get-VBRCDPPolicy | Select-Object Name, NextRun, PolicyState
	}
	catch {
		Write-Host "CDP jobs not supported"
		$cdpjobs = $false
	}

	if ($cdpjobs) {
		$myCdpJobsText = "<<<veeam_cdp_jobs:sep(124)>>>`n"

		foreach ($mycdpjobs in $cdpjobs) {
			$MyCdpJobsName = $mycdpjobs.Name -replace "\'", "_" -replace " ", "_"

			$MyCdpJobsNextRun = $mycdpjobs.NextRun
			if ($null -ne $MyCdpJobsNextRun) {
				$MyCdpJobsNextRun = Get-Date -Date $MyCdpJobsNextRun -UFormat %s
			}
			else {
				$MyCdpJobsNextRun = "null"
			}

			$MyCdpJobsPolicyState = $mycdpjobs.PolicyState

			$myCdpJobsText = "$myCdpJobsText" + "$MyCdpJobsName" + "|" + "$MyCdpJobsNextRun" + "|" + "$MyCdpJobsPolicyState" + "`n"
		}

		Write-Host $myCdpJobsText
	}

	#####################################
	## Backup Job
	#####################################
	$myJobsText = "<<<veeam_jobs:sep(9)>>>`n"
	$myTaskText = ""

	$myBackupJobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.IsScheduleEnabled -eq $true }

	foreach ($myJob in $myBackupJobs) {
		$myJobName = $myJob.Name -replace "\'", "_" -replace " ", "_"

		$myJobType = $myjob.JobType

		$myJobLastState = $myJob.GetLastState()

		$myJobLastResult = $myJob.GetLastResult()

		$myJobLastSession = $myJob.FindLastSession()

		$myJobCreationTime = $myJobLastSession.CreationTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue

		$myJobEndTime = $myJobLastSession.EndTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue

		$myJobsText = "$myJobsText" + "$myJobName" + "`t" + "$myJobType" + "`t" + "$myJobLastState" + "`t" + "$myJobLastResult" + "`t" + "$myJobCreationTime" + "`t" + "$myJobEndTime" + "`n"

		# TODO when should the last backup had started
		

		# For Non Backup Jobs (Replicas) we bail out
		# because we are interested in the status of the original backup but
		# for replicas the overall job state is all we need.
		if ($myJob.IsBackup -eq $false) { continue }

		# Each backup job has a number of tasks which were executed (VMs which were processed)
		# Get all Tasks of the  L A S T  backup session
		# Caution: Each backup job MAY have run SEVERAL times for retries,
		# thats why we need all sessions related to the last one if its a retry
		$sessions = @($myJobLastSession)
		if ($myJobLastSession.IsRetryMode) {
			$sessions = $myJobLastSession.GetOriginalAndRetrySessions($TRUE)
		}

		$myJobLastSessionTasks = $sessions | Get-VBRTaskSession -ErrorAction SilentlyContinue

		foreach ($myTask in $myJobLastSessionTasks) {
			$myTaskName = $myTask.Name -replace "[^ -x7e]" -replace " ", "_"

			$myTaskText = "$myTaskText" + "<<<<" + "$myTaskName" + ">>>>" + "`n"

			$myTaskText = "$myTaskText" + "<<<" + "veeam_client:sep(9)" + ">>>" + "`n"

			$myTaskStatus = $myTask.Status

			$myTaskText = "$myTaskText" + "Status" + "`t" + "$myTaskStatus" + "`n"

			$myTaskText = "$myTaskText" + "JobName" + "`t" + "$myJobName" + "`n"

			$myTaskTotalSize = $myTask.Progress.TotalSize

			$myTaskText = "$myTaskText" + "TotalSizeByte" + "`t" + "$myTaskTotalSize" + "`n"

			$myTaskReadSize = $myTask.Progress.ReadSize

			$myTaskText = "$myTaskText" + "ReadSizeByte" + "`t" + "$myTaskReadSize" + "`n"

			$myTaskTransferedSize = $myTask.Progress.TransferedSize

			$myTaskText = "$myTaskText" + "TransferedSizeByte" + "`t" + "$myTaskTransferedSize" + "`n"

			# Starting from Version 9.5U3 StartTime is not supported anymore
			if ($Null -eq $myTask.Progress.StartTime) {
				$myTaskStartTime = $myTask.Progress.StartTimeLocal
			}
			else {
				$myTaskStartTime = $myTask.Progress.StartTime
			}
			$myTaskStartTime = $myTaskStartTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue

			$myTaskText = "$myTaskText" + "StartTime" + "`t" + "$myTaskStartTime" + "`n"

			# Starting from Version 9.5U3 StopTime is not supported anymore
			if ($Null -eq $myTask.Progress.StopTime) {
				$myTaskStopTime = $myTask.Progress.StopTimeLocal
			}
			else {
				$myTaskStopTime = $myTask.Progress.StopTime
			}
			$myTaskStopTime = $myTaskStopTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue

			$myTaskText = "$myTaskText" + "StopTime" + "`t" + "$myTaskStopTime" + "`n"

			# Result is a value of type System.TimeStamp. I'm sure there is a more elegant way of formatting the output:
			$myTaskDuration = "" + "{0:D2}" -f $myTask.Progress.duration.Days + ":" + "{0:D2}" -f $myTask.Progress.duration.Hours + ":" + "{0:D2}" -f $myTask.Progress.duration.Minutes + ":" + "{0:D2}" -f $myTask.Progress.duration.Seconds

			$myTaskText = "$myTaskText" + "DurationDDHHMMSS" + "`t" + "$myTaskDuration" + "`n"

			$myTaskAvgSpeed = $myTask.Progress.AvgSpeed

			$myTaskText = "$myTaskText" + "AvgSpeedBps" + "`t" + "$myTaskAvgSpeed" + "`n"

			$myTaskDisplayName = $myTask.Progress.DisplayName

			$myTaskText = "$myTaskText" + "DisplayName" + "`t" + "$myTaskDisplayName" + "`n"

			$myBackupHost = Hostname

			$myTaskText = "$myTaskText" + "BackupServer" + "`t" + "$myBackupHost" + "`n"

			$myTaskText = "$myTaskText" + "<<<<" + ">>>>" + "`n"
		}
	}

	Write-Host $myJobsText
	Write-Host $myTaskText
}
catch {
	$errMsg = $_.Exception.Message
	$errItem = $_.Exception.ItemName
	Write-Error "Totally unexpected and unhandled error occured:`n Item: $errItem`n Error Message: $errMsg"
	Break
}

function Get-LastScheduledTapeBackupDate {
	param (
		$TapeJob
	)

	$mostRecentScheduledBackupDate = $null
	$today = Get-Date
	

	# Daily
	$dailyOptions = $TapeJob.ScheduleOptions.DailyOptions
	if (($null -ne $dailyOptions) -and ($TapeJob.ScheduleOptions.Type -eq [Veeam.Backup.PowerShell.Infos.VBRBackupToTapePolicyType]::Daily)) {
		$backupDays = $dailyOptions.DayOfWeek # Array of DayOfWeek Enum
		$baseDate = Get-Date -Year $today.Year `
			-Month $today.Month `
			-Day $today.Day `
			-Hour 0 `
			-Minute 0 `
			-Second 0 `
			-Millisecond 0
		$baseDate = $baseDate.Add($dailyOptions.Period)
		$backupDaysDate = foreach ($dayOfWeek in $backupDays) {
			$date = $baseDate.AddDays((-7 - $baseDate.DayOfWeek + $dayOfWeek) % 7)
			if ($date -lt $today) { $date } else { $date.AddDays(-7) }
		}
		$mostRecentScheduledBackupDate = $backupDaysDate | Sort-Object | Select-Object -Last 1
	}

	# Monthly
	$monthlyOptions = $TapeJob.ScheduleOptions.MonthlyOptions
	if (($null -ne $monthlyOptions) -and ($TapeJob.ScheduleOptions.Type -eq [Veeam.Backup.PowerShell.Infos.VBRBackupToTapePolicyType]::Monthly)) {
		$backupMonths = $monthlyOptions.Months
		$baseDate = Get-Date -Year $today.Year `
			-Month $today.Month `
			-Day 1 `
			-Hour 0 `
			-Minute 0 `
			-Second 0 `
			-Millisecond 0
		$baseDate = $baseDate.Add($monthlyOptions.Period)
		$backupMonthsBaseDate = foreach ($month in $backupMonths) {
			$baseDate.AddMonths((-12 - $baseDate.Month + $month) % 12)
		}
		$backupMonthsDate = foreach ($monthlyDate in $backupMonthsBaseDate) {
			switch ($monthlyOptions.DayNumberInMonth) {
				([Veeam.Backup.PowerShell.Infos.VBRDayNumberInMonth]::First) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					if ($date -lt $today) {
						$date
					}
					else {
						Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek 
					}
				}
				([Veeam.Backup.PowerShell.Infos.VBRDayNumberInMonth]::Second) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					$date = $date.AddDays(7)
					if ($date -lt $today) {
						$date
					}
					else {
						$date = Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
						$date = $date.AddDays(7)
						$date
					}
				}
				([Veeam.Backup.PowerShell.Infos.VBRDayNumberInMonth]::Third) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					$date = $date.AddDays(14)
					if ($date -lt $today) {
						$date
					}
					else {
						$date = Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
						$date = $date.AddDays(14)
						$date
					}
				}
				([Veeam.Backup.PowerShell.Infos.VBRDayNumberInMonth]::Fourth) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					$date = $date.AddDays(21)
					if ($date -lt $today) {
						$date
					}
					else {
						$date = Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
						$date = $date.AddDays(21)
						$date
					}
				}
				([Veeam.Backup.PowerShell.Infos.VBRDayNumberInMonth]::Last) {
					$date = Get-LastWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					if ($date -lt $today) {
						$date
					}
					else {
						Get-LastWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
					}
				}
				([Veeam.Backup.PowerShell.Infos.VBRDayNumberInMonth]::OnDay) {
					if ($monthlyOptions.DayOfMonth -eq "Last") {
						$daysInMonth = [datetime]::DaysInMonth($monthlyDate.Year, $monthlyDate.Month)
						$date = $monthlyDate.AddDays($daysInMonth - 1)
					}
					else {
						$days = [int]$monthlyOptions.DayOfMonth
						$date = $monthlyDate.AddDays($days - 1)
					}
					if ($date -lt $today) {
						$date
					}
					else {
						$date.AddMonths(-12)
					}
				}
			}
		}
		$mostRecentScheduledBackupDate = $backupMonthsDate | Sort-Object | Select-Object -Last 1
	}

	# After Job
	$afterJobId = $TapeJob.ScheduleOptions.JobId
	if (($null -ne $afterJobId) -and ($TapeJob.ScheduleOptions.Type -eq [Veeam.Backup.PowerShell.Infos.VBRBackupToTapePolicyType]::AfterJob)) {
		# TODO calculate last backup start date
	}

	# After New Backup
	$afterNewBackupSchedule = $TapeJob.ScheduleOptions.ScheduleOptions
	if (($null -ne $afterNewBackupSchedule) -and ($TapeJob.ScheduleOptions.Type -eq [Veeam.Backup.PowerShell.Infos.VBRBackupToTapePolicyType]::AfterNewBackup)) {
		# TODO calculate last backup start date
	}

	return $mostRecentScheduledBackupDate
}

function Get-LastScheduledBackupDate {
	param (
		$Job
	)

	$mostRecentScheduledBackupDate = $null
	$today = Get-Date
	
	# Daily
	$dailyOptions = $Job.ScheduleOptions.OptionsDaily
	if (($null -ne $dailyOptions) -and $dailyOptions.Enabled) {
		$backupDays = $dailyOptions.DaysSrv # Array of DayOfWeek Enum
		$baseDate = Get-Date -Year $today.Year `
			-Month $today.Month `
			-Day $today.Day `
			-Hour $dailyOptions.TimeLocal.Hour `
			-Minute $dailyOptions.TimeLocal.Minute `
			-Second $dailyOptions.TimeLocal.Second `
			-Millisecond $dailyOptions.TimeLocal.Millisecond
		$backupDaysDate = foreach ($dayOfWeek in $backupDays) {
			$date = $baseDate.AddDays((-7 - $baseDate.DayOfWeek + $dayOfWeek) % 7)
			if ($date -lt $today) { $date } else { $date.AddDays(-7) }
		}
		$mostRecentScheduledBackupDate = $backupDaysDate | Sort-Object | Select-Object -Last 1
	}

	# Monthly
	$monthlyOptions = $Job.ScheduleOptions.OptionsMonthly
	if (($null -ne $monthlyOptions) -and $monthlyOptions.Enabled) {
		$backupMonths = $monthlyOptions.Months
		$baseDate = Get-Date -Year $today.Year `
			-Month $today.Month `
			-Day 1 `
			-Hour $monthlyOptions.TimeLocal.Hour `
			-Minute $monthlyOptions.TimeLocal.Minute `
			-Second $monthlyOptions.TimeLocal.Second `
			-Millisecond $monthlyOptions.TimeLocal.Millisecond
		$backupMonthsBaseDate = foreach ($month in $backupMonths) {
			$baseDate.AddMonths((-12 - $baseDate.Month + $month) % 12)
		}
		$backupMonthsDate = foreach ($monthlyDate in $backupMonthsBaseDate) {
			switch ($monthlyOptions.DayNumberInMonth) {
				([Veeam.Backup.Common.EDayNumberInMonth]::First) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					if ($date -lt $today) {
						$date
					}
					else {
						Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek 
					}
				}
				([Veeam.Backup.Common.EDayNumberInMonth]::Second) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					$date = $date.AddDays(7)
					if ($date -lt $today) {
						$date
					}
					else {
						$date = Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
						$date = $date.AddDays(7)
						$date
					}
				}
				([Veeam.Backup.Common.EDayNumberInMonth]::Third) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					$date = $date.AddDays(14)
					if ($date -lt $today) {
						$date
					}
					else {
						$date = Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
						$date = $date.AddDays(14)
						$date
					}
				}
				([Veeam.Backup.Common.EDayNumberInMonth]::Fourth) {
					$date = Get-FirstWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					$date = $date.AddDays(21)
					if ($date -lt $today) {
						$date
					}
					else {
						$date = Get-FirstWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
						$date = $date.AddDays(21)
						$date
					}
				}
				([Veeam.Backup.Common.EDayNumberInMonth]::Last) {
					$date = Get-LastWeekDayInMonth $monthlyDate $monthlyOptions.DayOfWeek
					if ($date -lt $today) {
						$date
					}
					else {
						Get-LastWeekDayInMonth $monthlyDate.AddMonths(-12) $monthlyOptions.DayOfWeek
					}
				}
				([Veeam.Backup.Common.EDayNumberInMonth]::OnDay) {
					$date = $monthlyOptions.DayOfMonth.ToDate($monthlyDate)
					$date = $date.AddHours($monthlyOptions.TimeLocal.Hour)
					$date = $date.AddMinutes($monthlyOptions.TimeLocal.Minute)
					$date = $date.AddSeconds($monthlyOptions.TimeLocal.Second)
					$date = $date.AddMilliseconds($monthlyOptions.TimeLocal.Millisecond)
					if ($date -lt $today) {
						$date
					}
					else {
						$date.AddMonths(-12)
					}
				}
			}
		}
		$mostRecentScheduledBackupDate = $backupMonthsDate | Sort-Object | Select-Object -Last 1
	}

	# Continuous
	#TODO check if correct
	$continuousOptions = $Job.ScheduleOptions.OptionsContinuous
	if (($null -ne $continuousOptions) -and $continuousOptions.Enabled) {
		[xml]$xmlSchedule = $continuousOptions.Schedule
		$scheduler = $xmlSchedule.scheduler
		$baseDate = Get-Date -Year $today.Year `
			-Month $today.Month `
			-Day $today.Day `
			-Hour 0 `
			-Minute 59 `
			-Second 0 `
			-Millisecond 0

		$foundDate = $false
		$date = $baseDate
		$timeTable = @($scheduler.($date.DayOfWeek) -split ",")
		for ($hour = $today.Hour - 1; $hour -ge 0; $hour--) {
			if (($timeTable[$hour] -eq 0) -and !$foundDate) {				
				$date = $date.AddHours($hour)
				$foundDate = $true
			}
		}
		while (!$foundDate -and ($date -ne $baseDate.AddDays(-7))) {
			$date = $date.AddDays(-1)
			$timeTable = @($scheduler.($date.DayOfWeek) -split ",")
			for ($hour = $timeTable.Count - 1; $hour -ge 0; $hour--) {
				if (($timeTable[$hour] -eq 0) -and !$foundDate) {
					$date = $date.AddHours($hour)
					$foundDate = $true
				}
			}
		}
		if ($foundDate) { $mostRecentScheduledBackupDate = $date }
	}

	# Periodically
	$periodicallyOptions = $Job.ScheduleOptions.OptionsPeriodically
	if (($null -ne $periodicallyOptions) -and $periodicallyOptions.Enabled) {
		$xmlSchedule = [xml]$periodicallyOptions.Schedule
		$scheduler = $xmlSchedule.scheduler
		$baseDate = Get-Date -Year $today.Year `
			-Month $today.Month `
			-Day $today.Day `
			-Hour 0 `
			-Minute 59 `
			-Second 0 `
			-Millisecond 0
		# TODO calculate last backup start date
	}

	# After Job
	$afterJobOptions = $Job.ScheduleOptions.OptionsScheduleAfterJob
	if (($null -ne $afterJobOptions) -and $afterJobOptions.Enabled) {
		# no options
		# TODO find target backup job and get end time from last run
	}

	return $mostRecentScheduledBackupDate
}

function Get-FirstWeekDayInMonth {
	param (
		$Date,
		$DayOfWeek
	)

	while ($Date.DayOfWeek -ne $DayOfWeek) {
		$Date = $Date.AddDays(1)
	}
	return $Date
}

function Get-LastWeekDayInMonth {
	param (
		$Date,
		$DayOfWeek
	)

	$daysInMonth = [datetime]::DaysInMonth($Date.Year, $Date.Month)
	$Date = $Date.AddDays($daysInMonth - 1)
	while ($Date.DayOfWeek -ne $DayOfWeek) {
		$Date = $Date.AddDays(-1)
	}
	return $Date
}