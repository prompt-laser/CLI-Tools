function Top {
	<#
		.SYNOPSIS
		Top shows vital system stats including system uptime, logged on users,
		memory usage, and running processes sorted by CPU time used since last
		update
		
		.DESCRIPTION
		Top uses a variety of counters and built-in PowerShell commands to gather
		vital statistics on the target computer
	#>
	
	$polledProcesses = Get-Process
	while($true){
		#Calculate total/free memory
		$freeMem = (Get-Counter "\memory\available mbytes").readings.split("`n")[1]
		$totalMem = 0
		foreach($c in (get-wmiObject win32_physicalMemory).capacity){
			$totalMem += $c
		}
		
		#Get user count
		$users = @()
		foreach($u in (get-wmiobject win32_process |where {$_.name -eq "explorer.exe"}).getowner().user){
			$users += @($u)
		}
		$userCount = @($users).length
		
		#Calculate processor load
		$rawTimes = (get-counter "\processor information(*)\% processor time").readings
		$arrayTimes = $rawTimes.split("`n");
		$times = @()
		for($i = 5; $i -lt @($arrayTimes).length; $i = $i + 1){
			if($i % 3 -eq 1){
				$times += @($arrayTimes[$i])
			}
		}
		$totalTime = 0
		foreach($t in $times){
			$totalTime += $t
		}
		
		#Calculate systme uptime
		$uptime = new-timespan `
					([DateTime]::parseExact([string]((get-wmiobject win32_operatingsystem).lastbootuptime).split(".")[0],"yyyyMMddHHmmss", $null)) `
					(get-date)
					
		#Begin process polling and timing section
		$processes = @()
		$processes = Get-Process
		$tempPolledProcesses = @()
		foreach($p in $processes){
			$matched = $false
			foreach($pP in $polledProcesses){
				if($p.Id.Equals($pP.Process.Id)){
					$tempPolledProcesses += New-Object PSObject -Property @{
						"Process"=$p;
						"Span"=$p.TotalProcessorTime.TotalMilliseconds-$pP.MS;
						"MS"=$p.TotalProcessorTime.TotalMilliseconds
					}
					$matched = $true
				}
			}
			if(-not $matched){
				$tempPolledProcesses += New-Object PSObject -Property @{
					"Process"=$p;
					"Span"=$p.TotalProcessorTime.TotalSeconds-$p.TotalProcessorTime.TotalSeconds;
					"MS"=$p.TotalProcessorTime.TotalMilliSeconds
					}
			}
		}
		$polledProcesses = $tempPolledProcesses
		#End process polling and timing section
		
		#Maximum processes to show in output
		$maxLines = $host.UI.RawUI.WindowSize.Height - 8
		
		#Clear the screen and write output
		cls
		Write-Host "up" $uptime.days "days," $uptime.hours ":" $uptime.minutes ", " $userCount " users, load:" ([string]($totalTime / 100)).substring(0,4)
		Write-Host "MB Memory: `t" ($totalMem/1MB) "total,`t" $freeMem "free,`t" ($totalMem/1MB - $freeMem) "used"
		$polledProcesses | Sort-Object -Property Span,MS -Desc| Select-Object -First $maxLines -Expand Process | Format-Table
	}
}