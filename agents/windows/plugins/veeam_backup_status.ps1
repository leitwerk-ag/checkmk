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
	$tapeJobs = Get-VBRTapeJob -WarningAction SilentlyContinue | Where-Object { $_.ScheduleOptions.Enabled -or $_.FullBackupPolicy.Enabled -or $_.IncrementalBackupPolicy.Enabled }
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

