function Get-RunningSnapshot {
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
		$maxLines = $host.UI.RawUI.WindowSize.Height - 9
		
		#Current time string
		$strSystemTime = (get-date).Hour.ToString().PadLeft(2,"0") + `
			":" + (Get-Date).Hour.Tostring().PadLeft(2,"0") + `
			":" + (Get-Date).Second.ToString().PadLeft(2,"0")
		
		#Uptime string
		$strUptime = "up " + $uptime.days + " day(s), " + `
			$uptime.hours.ToString().PadLeft(2,"0") + ":" + $uptime.minutes.ToString().PadLeft(2,"0")
		
		#Top line of output
		$topLine = $strSystemTime + " " + $strUptime + ",`t" + $userCount + " users,`tload: " + ([string]($totalTime / 100)).substring(0,4)
		
		#Get total process counts
		$cntProcesses = $polledProcesses.Length
		#Get number of processes that have used CPU since last update
		$cntRunningProcesses = ($polledProcesses | Where-Object {$_.Span -gt 0 }).Length
		#Get number of sleeping processes. We're assuming if it hasn't used CPU that it is asleep
		$cntSleepingProcesses = $cntProcesses - $cntRunningProcesses
		
		#Tasks (2nd) line of output
		$secondLine = "Tasks:`t" + $cntProcesses + " total,`t" + $cntRunningProcesses + " running,`t" + $cntSleepingProcesses + " sleeping"
		
		#Clear the screen and write output
		cls
		Write-Host $topLine
		Write-Host $secondLine
		Write-Host "MB Memory:`t`t" ($totalMem/1MB) "total,`t" $freeMem "free,`t" ($totalMem/1MB - $freeMem) "used"
		$polledProcesses | Sort-Object -Property Span,MS -Desc | Select-Object -First $maxLines -Expand Process | Format-Table
	}
}

function Get-NetworkHosts {
    <#
        .SYNOPSIS
        Does a ping scan of a subnet for reachable hosts
   
        .PARAMETER IPAddress
        Address in the subnet you wish to scan
   
        .PARAMETER NetworkBits
        Number of bits in the network
   
        .PARAMETER SubnetMask
        Subnet mask of the network
		
		.PARAMETER ReachableOnly
		Return only the hosts that are reachable. Defaults to true
       
        .PARAMETER Timeout
        Timeout for ping requests. Defaults to 500ms
		
		.EXAMPLE
		Get-NetworkHosts 192.168.0.0 24
		
		Return all hosts that are up in the 192.168.0.0/24 subnet
		
		.EXAMPLE
		Get-NetworkHosts 192.168.0.0 24 $false
		
		Return all hosts in the 192.168.0.0/24 subnet regardless of whether they are up or down
    #>
 
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$IPAddress,
        [Parameter(ParameterSetName='Mask',Mandatory=$true,Position=1)]
        [string]$SubnetMask,
        [Parameter(ParameterSetName='Bits',Mandatory=$true,Position=1)]
        [int]$NetworkBits,
		[Parameter(Mandatory=$false,Position=2)]
		[bool]$ReachableOnly = $true,
        [Parameter(Mandatory=$false,Position=3)]
        [int]$Timeout = 500
    )
 
    function toBinary($dottedDecimal){
        $dottedDecimal.split(".") | %{$binary=$binary + $([convert]::toString($_,2).padleft(8,"0"))}
        return $binary
    }
 
    function toDottedDecimal ($binary){
        $i = 0
        do {$dottedDecimal += "." + [string]$([convert]::toInt32($binary.substring($i,8),2)); $i+=8 } while ($i -le 24)
        return $dottedDecimal.substring(1)
    }
 
    If($SubnetMask){
        $bnSubnet = toBinary($SubnetMask)
        $NetworkBits = $bnSubnet.IndexOf("0")
    }
    $bnAddress = toBinary($IPAddress)
    $StaticBits = $bnAddress.substring(0,$NetworkBits)
 
    $CurrentAddress = 1
    $LastAddress = "0".padleft(32-$NetworkBits,"1")
    $Addresses = @()
    $i = 0
    While($CurrentAddress -le ([Convert]::ToInt32($LastAddress,2))){
        $wrkAddress = [Convert]::ToString($CurrentAddress,2).padleft(32-$NetworkBits,"0")
        $wrkAddress = -join($StaticBits,$wrkAddress)
        $wrkAddress = toDottedDecimal($wrkAddress)
        If( (Get-WmiObject Win32_PingStatus -Filter "Address='$wrkAddress' and Timeout=$Timeout").ReplySize -ne $null ){
            $Addresses += New-Object PSObject -Property @{
                'IPAddress' = $wrkAddress
                'Up' = $true
            }
        }Else{
            $Addresses += New-Object PSObject -Property @{
                'IPAddress' = $wrkAddress
                'Up' = $false
            }
        }
        Write-Progress -Activity "Finding Hosts" -PercentComplete ($CurrentAddress/([Convert]::toInt32($LastAddress,2))*100)
        $CurrentAddress = $CurrentAddress + 1
        $i = $i + 1
        $wrkAddress = ""
    }
	if($ReachableOnly){
		return $Addresses | Where-Object {$_.Up -eq $true}
	}else{
		return $Addresses
	}
}

function Get-Memory {
	<#
		.SYNOPSIS
		Get-Memory gives a quick snapshot of total system memory, the amount of memory used,
		and the amount available for allocation
	#>
	
	$totalMem = 0
	ForEach($c in (Get-WmiObject Win32_PhysicalMemory).Capacity){
		$totalMem += $c
	}

	$freeMem = (Get-Counter "\memory\available mbytes").Readings.Split("`n")[1]

	$usedMem = $totalMem/1MB - $freeMem
	
	$memory = New-Object PSObject -Property @{
		'Total'	= $totalMem/1MB;
		'Used'	= $usedMem;
		'Free'	= $freeMem;
	}
	
	return $memory
}

function Get-DriveSpace {
	<#
		.SYNOPSIS
		Get-DriveSpace gives a quick snapshot of system volumes. It shows the filesystem, size
		of disk, free space, used percentage, and mountpoints
		
		.PARAMETER Human
		Formats space to human readable numbers.
	#>
	
	param(
		[Parameter(Mandatory=$false,Position=0)]
		[switch]$Human
	)
	
	function FormatHumanReadable($number) {
		if($number / 1pb -gt 1){
			return ($number / 1pb).ToString("#.##") + "pB"
		}elseif($number / 1tb -gt 1){
			return ($number / 1tb).ToString("#.##") + "tB"
		}elseif($number / 1gb -gt 1){
			return ($number / 1gb).ToString("#.##") + "gB"
		}elseif($number / 1mb -gt 1){
			return ($number / 1mb).ToString("#.##") + "mB"
		}elseif($number / 1kb -gt 1){
			return ($number / 1kb).ToString("#.##") + "kB"
		}else{
			return $number
		}
	}
		
	$rawDisks = Get-WmiObject Win32_Volume | Where-Object {$_.Caption -notlike "\\*"}
	$disks = @()
	foreach($d in $rawDisks){
		if($Human){
			$disks += New-Object PSObject -Property @{
				'FileSystem'	= $d.FileSystem;
				'Size'			= FormatHumanReadable($d.Capacity);
				'Free'			= FormatHumanReadable($d.FreeSpace);
				'Use%'			= [int](($d.FreeSpace / $d.Capacity) * 100);
				'MountPoint'	= $d.Name;
			}
		}else{
			$disks += New-Object PSObject -Property @{
				'FileSystem'	= $d.FileSystem;
				'Size'			= $d.Capacity;
				'Free'			= $d.FreeSpace;
				'Use%'			= [int]($d.FreeSpace / $d.Capacity);
				'MountPoint'	= $d.Name;
			}
		}
	}
	
	
	return $disks | Format-Table	
}

function Get-RegExMatches {	
	<#
		.SYNOPSIS
		Get-RegExMatches searches an input string for matches to the pattern parameter
		
		.PARAMETER Pattern
		RegEx pattern to search the input object for
		
		.PARAMETER InputObject
		Text to search
	#>
	
	param(
		[Parameter(Mandatory=$true,Position=0)]
		[String]$Pattern,
		
		[Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true)]
		[String[]]$InputObject
	)
	
	process{
		$matches = @()
		
		foreach($line in $InputObject){
			if($line -like ("*" + $Pattern + "*")){
				$matches += $line
			}
		}
		
		return $matches
	}
}

function New-File {
	<#
		.SYNOPSIS
		New-EmptyFile will create a new empty file at the provided location
		
		.PARAMETER Location
		Location to create the new file. Just a filename will create it in the current directory.
	#>
	
	param(
		[Parameter(Mandatory=$true,Position=0)]
		[String]$Location
	)
	
	$null | Out-File $location
}
	
	

New-Alias -Name free -Value Get-Memory
New-Alias -Name top -Value Get-RunningSnapshot
New-Alias -Name df -Value Get-DriveSpace
New-Alias -Name grep -Value Get-RegExMatches
New-Alias -Name touch -Value New-File

Export-ModuleMember -Alias * -Function *