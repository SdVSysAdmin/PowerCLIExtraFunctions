# PowerCLIExtraFunctions

Adds a few extra functions to PowerCLI based on things available in RVC.

Right now only has a few VSAN things, but I may add more as I get time. Shout out to @lamw for the idea.

### Get-VsanDiskStats (vsan.disks_stats .)
```
. .\ExtraVSANFunctions.ps1
Get-VsanDiskStats -Cluster <YOUR_VSAN_CLUSTER>
```

### Get-VSANProactiveRebalanceInfo (vsan.proactive_rebalance_info .)
```
. .\ExtraVSANFunctions.ps1

#get credential for your ESXI hosts
$cred = Get-Credential

Get-VSANProactiveRebalanceInfo -vCenter <YOUR_VCENTER> -Cluster <YOUR_VSAN_CLUSTER> -Credential $cred
```