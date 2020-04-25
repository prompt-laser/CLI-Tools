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
	While($true){
		#Calculate total/free memory
		$freeMem = (Get-Counter "\memory\available mbytes").Readings.Split("`n")[1]
		$totalMem = 0
		ForEach($c in (Get-WmiObject Win32_PhysicalMemory).Capacity){
			$totalMem += $c
		}
		
		#Get user count
		$users = @()
		ForEach($u in (Get-WmiObject Win32_Process | Where-Object { $_.Name -eq "explorer.exe" }).GetOwner().User){
			$users += @($u)
		}
		$userCount = @($users).length
		
		#Calculate processor load
		$rawTimes = (Get-Counter "\Processor Information(*)\% Processor Time").Readings
		$arrayTimes = $rawTimes.Split("`n");
		$times = @()
		For($i = 5; $i -lt @($arrayTimes).Length; $i = $i + 1){
			If($i % 3 -eq 1){
				$times += @($arrayTimes[$i])
			}
		}
		$totalTime = 0
		ForEach($t in $times){
			$totalTime += $t
		}
		
		#Calculate systme uptime
		$uptime = New-Timespan `
					([DateTime]::parseExact([string]((Get-WmiObject Win32_OperatingSystem).LastBootupTime).Split(".")[0],"yyyyMMddHHmmss", $null)) `
					(Get-Date)
					
		#Begin process polling and timing section
		$processes = @()
		$processes = Get-Process
		$tempPolledProcesses = @()
		ForEach($p in $processes){
			$matched = $false
			ForEach($pP in $polledProcesses){
				if($p.Id.Equals($pP.Process.Id)){
					$tempPolledProcesses += New-Object PSObject -Property @{
						"Process"	= $p;
						"Span"		= $p.TotalProcessorTime.TotalMilliseconds - $pP.MS;
						"MS"		= $p.TotalProcessorTime.TotalMilliseconds
					}
					$matched = $true
				}
			}
			if(-not $matched){
				$tempPolledProcesses += New-Object PSObject -Property @{
					"Process"	= $p;
					"Span"		= $p.TotalProcessorTime.TotalSeconds-$p.TotalProcessorTime.TotalSeconds;
					"MS"		= $p.TotalProcessorTime.TotalMilliSeconds
					}
			}
		}
		$polledProcesses = $tempPolledProcesses
		#End process polling and timing section
		
		#Maximum processes to show in output
		$maxLines = $host.UI.RawUI.WindowSize.Height - 8
		
		#Clear the screen and write output
		cls
		Write-Host "up" $uptime.days "days," $uptime.hours.ToString().PadLeft(2,"0") ":" $uptime.minutes.ToString().PadLeft(2,"0") ", " $userCount " users, load:" ([string]($totalTime / 100)).substring(0,4)
		Write-Host "MB Memory: `t" ($totalMem/1MB) "total,`t" $freeMem "free,`t" ($totalMem/1MB - $freeMem) "used"
		$polledProcesses | Sort-Object -Property Span,MS -Desc | Select-Object -First $maxLines -Expand Process | Format-Table
	}
}