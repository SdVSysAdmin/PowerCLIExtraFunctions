<#PSScriptInfo
.VERSION 1.1
.GUID 4e9ee514-64cb-430d-afc9-fb0b24ca6c3b
.AUTHOR Ray Terrill
.COMPANYNAME Port of Portland
.DESCRIPTION This function tries to reconstruct several "vsan.disks_stats commands ." does using PowerCLI. Shout out to @lamw for the idea.
#>
<#
    .NOTES
    ===========================================================================
     Created by:    Ray Terrill
     Organization:  Port of Portland
     Twitter:       @rayterrill
        ===========================================================================
    .DESCRIPTION
        This function tries to reconstruct what the RVC command "vsan.disks_stats ." does using PowerCLI. Shout out to @lamw for the idea.
    .PARAMETER Cluster
        The name of a vSAN Cluster
    .EXAMPLE
        Get-VsanLimits -Cluster VSAN-Cluster
#>

Function Get-VsanDiskStats {
    param(
        [Parameter(Mandatory=$true)][String]$Cluster
    )
    
   $vmhosts = (Get-Cluster -Name $Cluster | Get-VMHost | Sort-Object -Property Name)

   $totalDiskData = @()
   $totalDiskMetadata = @()
   
   foreach($vmhost in $vmhosts) {
      $connectionState = $vmhost.ExtensionData.Runtime.runtime.connectionState
      $vsanEnabled = (Get-View $vmhost.ExtensionData.ConfigManager.vsanSystem).config.enabled

      if($connectionState -ne "Connected" -and $vsanEnabled -ne $true) {
         break
      }

      $vsanInternalSystem = Get-View $vmhost.ExtensionData.ConfigManager.vsanInternalSystem
      $data = $vsanInternalSystem.QueryPhysicalVsanDisks(@('lsom_objects_count','uuid','isSsd','capacity','capacityUsed','capacityReserved','logicalCapacity','logicalCapacityUsed','logicalCapacityReserved','physDiskCapacity','physDiskCapacityUsed','physDiskCapacityReserved','iops','iopsReserved','disk_health','formatVersion','publicFormatVersion','ssdCapacity','self_only'))
      $totalDiskData += $data

      $esxcli = Get-ESXCLI -VMHost $vmhost -V2
      $storage = $esxcli.vsan.storage.list.Invoke()
      $storage | Add-Member NoteProperty Host $vmhost
      $totalDiskMetadata += $storage
   }

   $results = @()

   $jsontotalDiskData = $totalDiskData | ConvertFrom-JSON

   foreach ($m in $totalDiskMetadata) {
      $obj = New-Object PSObject

      #match up the disk info with our metadata
      $diskInfo = $jsontotalDiskData.($m.VSANUUID)

      $obj | Add-Member NoteProperty DisplayName $m.DisplayName
      $obj | Add-Member NoteProperty Host $m.Host
      $obj | Add-Member NoteProperty isSSD $diskInfo.isSSD

      if ($diskInfo.isSSD) {
         $capacity = [math]::Round($diskInfo.ssdCapacity / 1024 / 1024 / 1024, 2)
      } else {
         $capacity = [math]::Round($diskInfo.Capacity / 1024 / 1024 / 1024, 2)
      }
      $obj | Add-Member NoteProperty "Capacity Total" $capacity

      $capacityUsedPercent = [math]::Round(($diskInfo.CapacityUsed/$diskInfo.Capacity * 100), 2)
      $capacityUsed = [math]::Round($diskInfo.CapacityUsed / 1024 / 1024 / 1024, 2)
      $obj | Add-Member NoteProperty "CapacityUsed" $capacityUsed
      $obj | Add-Member NoteProperty "Used" $capacityUsedPercent

      $reserved = [math]::Round(($diskInfo.CapacityReserved/$diskInfo.Capacity * 100), 2)
      $obj | Add-Member NoteProperty "Reserved" $reserved
      
      $physicalCapacity = [math]::Round($diskInfo.physDiskCapacity / 1024 / 1024 / 1024, 2)
      $obj | Add-Member NoteProperty "Physical Capacity" $physicalCapacity
      
      if ($physicalCapacity -eq 0) {
         $physicalUsed = 0
         $physicalReserved = 0
      } else {
         $physicalUsed = [math]::Round(($diskInfo.physDiskCapacityUsed/$diskInfo.physDiskCapacity * 100), 2)
         $physicalReserved = [math]::Round(($diskInfo.physDiskCapacityReserved/$diskInfo.physDiskCapacity * 100), 2)
      }
      $obj | Add-Member NoteProperty "Physical Used" $physicalUsed
      $obj | Add-Member NoteProperty "Physical Reserved" $physicalReserved
      
      $logicalCapacity = [math]::Round($diskInfo.logicalCapacity / 1024 / 1024 / 1024, 2)
      $obj | Add-Member NoteProperty "Logical Capacity" $logicalCapacity

      if ($logicalCapacity -eq 0) {
         $logicalUsed = 0
         $logicalReserved = 0
      } else {
         $logicalUsed = [math]::Round(($diskInfo.logicalCapacityUsed/$diskInfo.logicalCapacity * 100), 2)
         $logicalReserved = [math]::Round(($diskInfo.logicalCapacityReserved/$diskInfo.logicalCapacity * 100), 2)
      }
      $obj | Add-Member NoteProperty "Logical Used" $logicalUsed
      $obj | Add-Member NoteProperty "Logical Reserved" $logicalReserved
      
      #add the object to the results array
      $results += $obj
   }
   
   return $results
}

Function Get-VSANProactiveRebalanceInfo {
   param(
      [Parameter(Mandatory=$true)][String]$vCenter,
      [Parameter(Mandatory=$true)][String]$Cluster,
      [Parameter(Mandatory=$true)][System.Management.Automation.PSCredential]$credential
   )
   
   Connect-VIServer $vCenter | Out-Null
   $vmhosts = (Get-Cluster -Name $Cluster | Get-VMHost | Sort-Object -Property Name)
   
   #just getting the 1st host and first set of values.
   #not trying to mimic the rvc logic to get all hosts and make sure the values are consistent right now
   Connect-VIServer $vmhosts[0].Name -Credential $credential | Out-Null
   $view = Get-VSANView HostVsanHealthSystem-ha-vsan-health-system
   $rebalanceInfo = $view.VSanGetProactiveReBalanceInfo()[0]
   Disconnect-VIServer $vmhosts[0].Name -Confirm:$false
   
   if ($rebalanceInfo.Running) {
      $varianceThreshold = [math]::Round($rebalanceInfo.VarianceThreshold * 100,2)
   } else {
      $varianceThreshold = 30.00
   }
   $disks = Get-VSANDiskStats -cluster $cluster
   $disks = $disks | Where-Object {$_.isSSD -ne 1}
   
   $maxFullness = 0
   $minFullness = 1
   foreach ($d in $disks) {
      $fullness = $d.CapacityUsed/$d.'Capacity Total'
      $meanFullness = $meanFullness + $fullness
      if ($fullness -gt $maxFullness) { $maxFullness = $fullness }
      if ($fullness -lt $minFullness) { $minFullness = $fullness }
   }
   
   $meanFullness = [math]::Round($meanFullness / $disks.length * 100,2)
   $maxFullness = [math]::Round($maxFullness * 100,2)
   $minFullness = [math]::Round($minFullness * 100,2)
   $minToMaxFullnessDiff = $maxFullness - $minFullness
   $avgVariance = $meanFullness - $minFullness

   $string = "Max usage difference triggering rebalancing: " + $varianceThreshold + "%"
   Write-Host $string
   Write-Host "Average disk usage: $($meanFullness)%"
   Write-Host "Maximum disk usage: $($maxFullness)% ($($minToMaxFullnessDiff)% above minimum disk usage)"
   Write-Host "Imbalance index: $($avgVariance)%"
}