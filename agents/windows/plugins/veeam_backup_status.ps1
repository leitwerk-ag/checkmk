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

#####################################
## Functions
#####################################

function Write-TapeJobs {
	$tapeJobs = Get-VBRTapeJob -WarningAction SilentlyContinue | Where-Object { $_.Enabled -and ($_.ScheduleOptions.Enabled -or $_.FullBackupPolicy.Enabled -or $_.IncrementalBackupPolicy.Enabled) }
	Write-Host "<<<veeam_tapejobs:sep(124):encoding(cp437)>>>"

	foreach ($tapeJob in $tapeJobs) {
		$jobName = $tapeJob.Name
		$jobID = $tapeJob.Id
		$jobType = $tapeJob.Type

		$sessions = @(Get-VBRTapeBackupSession -Job $tapeJob | Sort-Object CreationTime -Descending)
		$lastFinischedSession = $sessions | Where-Object { $_.Progress -ge 100 } | Select-Object -First 1
		$scheduleType = [string]$tapeJob.ScheduleOptions.Type
		if ($null -ne $lastFinischedSession -and $scheduleType -eq "AfterNewBackup") {
			$lastSession = $lastFinischedSession
		}
		else {
			$lastSession = $sessions[0]
		}

		$lastResult = $lastSession.Result
		$lastState = $lastSession.State
		
		if ($null -ne $lastSession) {
			$creationTime = $lastSession.CreationTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue
			$endTime = $lastSession.EndTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue

			$errorLog = $lastSession.Log | Where-Object { $_.Status -ne [Veeam.Backup.PowerShell.Infos.VBRLogStatus]::Succeeded }
			$logErrorMessages = $errorLog.Title -replace "`n", "; " -replace "`r", "" -join "^"
		}

		Write-Host "$jobName|$jobID|$jobType|$lastResult|$lastState|$creationTime|$endTime|$logErrorMessages"
	}
}

function Write-CDPJobs {
	try {
		$cdpjobs = Get-VBRCDPPolicy | Select-Object Name, NextRun, PolicyState
	}
	catch {
		Write-Host "CDP jobs not supported"
		$cdpjobs = $false
	}

	if ($cdpjobs) {
		$myCdpJobsText = "<<<veeam_cdp_jobs:sep(124):encoding(cp437)>>>`n"

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
}

function Write-BackupJobs {
	$backupJobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.IsScheduleEnabled -and !$_.Options.JobOptions.RunManually }
	$jobsText = "<<<veeam_jobs:sep(124):encoding(cp437)>>>`n"
	$taskText = ""
	foreach ($job in $backupJobs) {
		$jobName = $job.Name -replace "\'", "_" -replace " ", "_"
		$jobType = $job.JobType
		$jobId = $job.Id

		$lastSession = $job.FindLastSession()	
			
		$lastState = $lastSession.State
		$lastResult = $lastSession.Result 

		if ($null -ne $lastSession) {
			if ($null -ne $lastSession.Logger) {
				$jobErrorLog = $lastSession.Logger.GetLog().UpdatedRecords
				$logErrorMessages = ($jobErrorLog | Where-Object { $_.Status -ne [Veeam.Backup.Common.ETaskLogRecordStatus]::ESucceeded }).Title -replace "`n", "; " -replace "`r", "" -join "^"
			}

			$creationTime = $lastSession.CreationTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue
			$endTime = $lastSession.EndTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue
		}

		$jobsText = "$jobsText$jobName|$jobId|$jobType|$lastResult|$lastState|$creationTime|$endTime|$logErrorMessages`n"
        
		# For Non Backup Jobs (Replicas) we bail out
		# because we are interested in the status of the original backup but
		# for replicas the overall job state is all we need.
		if ($job.IsBackup -eq $false) { continue }

		# Each backup job has a number of tasks which were executed (VMs which were processed)
		# Get all Tasks of the  L A S T  backup session
		# Caution: Each backup job MAY have run SEVERAL times for retries,
		# thats why we need all sessions related to the last one if its a retry
		$sessions = @($lastSession)
		if ($jobLastSession.IsRetryMode) {
			$sessions = $lastSession.GetOriginalAndRetrySessions($TRUE)
		}

		$jobLastSessionTasks = $sessions | Get-VBRTaskSession -ErrorAction SilentlyContinue

		foreach ($task in $jobLastSessionTasks) {
			$taskName = $task.Name -replace "[^ -x7e]" -replace " ", "_"
			$taskText = "$taskText" + "<<<<" + "$taskName" + ">>>>" + "`n"
			$taskText = "$taskText" + "<<<" + "veeam_client:sep(9):encoding(cp437)" + ">>>" + "`n"

			$taskStatus = $task.Status
			$taskText = "$taskText" + "Status" + "`t" + "$taskStatus" + "`n"

			$taskText = "$taskText" + "JobName" + "`t" + "$jobName" + "`n"

			$taskTotalSize = $task.Progress.TotalSize
			$taskText = "$taskText" + "TotalSizeByte" + "`t" + "$taskTotalSize" + "`n"

			$taskReadSize = $task.Progress.ReadSize
			$taskText = "$taskText" + "ReadSizeByte" + "`t" + "$taskReadSize" + "`n"

			$taskTransferedSize = $task.Progress.TransferedSize
			$taskText = "$taskText" + "TransferedSizeByte" + "`t" + "$taskTransferedSize" + "`n"

			# Starting from Version 9.5U3 StartTime is not supported anymore
			if ($Null -eq $task.Progress.StartTime) {
				$taskStartTime = $task.Progress.StartTimeLocal
			}
			else {
				$taskStartTime = $task.Progress.StartTime
			}
			$taskStartTime = $taskStartTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue
			$taskText = "$taskText" + "StartTime" + "`t" + "$taskStartTime" + "`n"

			# Starting from Version 9.5U3 StopTime is not supported anymore
			if ($Null -eq $task.Progress.StopTime) {
				$taskStopTime = $task.Progress.StopTimeLocal
			}
			else {
				$taskStopTime = $task.Progress.StopTime
			}
			$taskStopTime = $taskStopTime | Get-Date -Format "dd.MM.yyyy HH\:mm\:ss" -ErrorAction SilentlyContinue
			$taskText = "$taskText" + "StopTime" + "`t" + "$taskStopTime" + "`n"

			# Result is a value of type System.TimeStamp. I'm sure there is a more elegant way of formatting the output:
			$taskDuration = "" + "{0:D2}" -f $task.Progress.duration.Days + ":" + "{0:D2}" -f $task.Progress.duration.Hours + ":" + "{0:D2}" -f $task.Progress.duration.Minutes + ":" + "{0:D2}" -f $task.Progress.duration.Seconds
			$taskText = "$taskText" + "DurationDDHHMMSS" + "`t" + "$taskDuration" + "`n"

			$taskAvgSpeed = $task.Progress.AvgSpeed
			$taskText = "$taskText" + "AvgSpeedBps" + "`t" + "$taskAvgSpeed" + "`n"

			$taskDisplayName = $task.Progress.DisplayName
			$taskText = "$taskText" + "DisplayName" + "`t" + "$taskDisplayName" + "`n"

			$backupHost = Hostname
			$taskText = "$taskText" + "BackupServer" + "`t" + "$backupHost" + "`n"
			$taskText = "$taskText" + "<<<<" + ">>>>" + "`n"
		}
	}

	Write-Host $jobsText
	Write-Host $taskText
}

#####################################
## Main
#####################################

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
	Write-TapeJobs
	Write-CDPJobs
	Write-BackupJobs
}
catch {
	$errMsg = $_.Exception.Message
	$errItem = $_.Exception.ItemName
	Write-Error "Totally unexpected and unhandled error occured:`n Item: $errItem`n Error Message: $errMsg"
	Break
}