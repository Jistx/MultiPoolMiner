using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject[]]$Devices
)

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\$($Name)\nsgminer.exe"
$HashSHA256 = "5FD5F65E360E93C7A520DA5E1945E58F8AD6B1CF9ECBDF2E4D5FB06DEDD2C6A8"
$Uri = "https://github.com/MultiPoolMiner/miner-binaries/releases/download/NsgMiner/nsgminer-win64-0.9.4.zip"
$ManualUri = "https://github.com/ghostlander/nsgminer"

$Miner_Config = Get-MinerConfig -Name $Name -Config $Config

$Commands = [PSCustomObject]@{ 
    "neoscrypt" = " --neoscrypt" #NeoScrypt
}
#Commands from config file take precedence
if ($Miner_Config.Commands) { $Miner_Config.Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Commands | Add-Member $_ $($Miner_Config.Commands.$_) -Force } }

#CommonCommands from config file take precedence
if ($Miner_Config.CommonCommands) { $CommonCommands = $Miner_Config.CommonCommands }
else { $CommonCommands = " --text-only --worksize 64 --intensity 15" }

$Devices = @($Devices | Where-Object Type -EQ "GPU")
$Devices | Select-Object Vendor, Model -Unique | ForEach-Object { 
    $Miner_Device = @($Devices | Where-Object Vendor -EQ $_.Vendor | Where-Object Model -EQ $_.Model)
    $Miner_Port = [UInt16]($Config.APIPort + ($Miner_Device | Select-Object -First 1 -ExpandProperty Id) + 1)

    $Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Algorithm_Norm = Get-Algorithm $_; $_ } | Where-Object { $Pools.$Algorithm_Norm.Name -ne "Nicehash" <#miner does not understand NiceHash#> } | Where-Object { $Pools.$Algorithm_Norm.Protocol -eq "stratum+tcp" <#temp fix#> } | ForEach-Object { 
        $Miner_Name = (@($Name) + @($Miner_Device.Model | Sort-Object -unique | ForEach-Object { $Model = $_; "$(@($Miner_Device | Where-Object Model -eq $Model).Count)x$Model" }) | Select-Object) -join '-'

        #Get commands for active miner devices
        $Command = Get-CommandPerDevice -Command $Commands.$_ -ExcludeParameters @("algorithm", "k", "kernel") -DeviceIDs $Miner_Device.Type_Vendor_Index

        #Allow time to build binaries
        if (-not (Get-Stat "$($Miner_Name)_$($Algorithm_Norm)_HashRate")) { $WarmupTime = 90 } else { $WarmupTime = 30 }

        [PSCustomObject]@{ 
            Name               = $Miner_Name
            BaseName           = $Miner_BaseName
            Path               = $Path
            HashSHA256         = $HashSHA256
            Arguments          = ("$Command$CommonCommands --api-listen --api-port $Miner_Port --url $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) --user $($Pools.$Algorithm_Norm.User) --pass $($Pools.$Algorithm_Norm.Pass) --gpu-platform $($Miner_Device | Select-Object -First 1 -ExpandProperty PlatformID) --device $(($Miner_Device | ForEach-Object { '{0:x}' -f ($_.Type_PlatformId_Index) }) -join ' --device ')" -replace "\s+", " ").trim()
            HashRates          = [PSCustomObject]@{ $Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week }
            API                = "Xgminer"
            Port               = $Miner_Port
            URI                = $Uri
            IntervalMultiplier = 2
            WarmupTime         = $WarmupTime #seconds
        }
    }
}
