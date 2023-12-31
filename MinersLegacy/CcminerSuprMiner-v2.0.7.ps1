using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject[]]$Devices
)

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\$($Name)\ccminer.exe"
$HashSHA256 = "32E36BD667A3CCF49C3394C40E2FF15DE0ADDBA8E25C093F952E26157854FDC4"
$Uri = "https://github.com/ocminer/suprminer/releases/download/2.0/suprminer-2.0.7z"
$ManualUri = "https://github.com/ocminer/suprminer"

$Miner_Config = Get-MinerConfig -Name $Name -Config $Config

$Commands = [PSCustomObject]@{ 
    "bitcore"    = " -a bitcore" #Timetravel10 and Bitcore are technically the same
    "blake2s"    = " -a blake2s" #Blake2s
    "blakecoin"  = " -a blakecoin" #Blakecoin
    # "c11"        = " -a c11" #C11, NVIDIA-CcminerAlexis_v1.5 is faster
    "hmq1725"    = " -a hmq1725" #HMQ1725
    "hsr"        = " -a hsr" #HSR
    "keccak"     = " -a keccak" #Keccak
    "keccakc"    = " -a keccakc" #Keccakc
    "lyra2v2"    = " -a lyra2v2" #Lyra2RE2
    "lyra2z"     = " -a lyra2z" #Lyra2z
#    "neoscrypt"  = " -a neoscrypt --intensity 21.6" #NeoScrypt, CcminerKlausT-v8.25 is faster
    "phi"        = " -a phi" #PHI
    "skunk"      = " -a skunk" #Skunk
    "timetravel" = " -a timetravel" #Timetravel
    "tribus"     = " -a tribus" #Tribus
    "x11evo"     = " -a x11evo" #X11evo
    "x16r"       = " -a x16r" #X16R
    "x16rtveil"  = " -a x16rt" #X16Rt, for Veil only (see https://github.com/ocminer/suprminer/issues/5)
    "x16s"       = " -a x16s" #X16S
    #"x17"        = " -a x17" #X17, NVIDIA-CcminerAlexis_v1.5 is faster
    
    # ASIC - never profitable 06/08/2019
    #"decred"     = " -a decred" #Decred
    #"groestl"    = " -a groestl" #Groestl
    #"lbry"       = " -a lbry" #Lbry
    #"myr-gr"     = " -a myr-gr" #MyriadGroestl
    #"nist5"      = " -a nist5" #Nist5
    #"qubit"      = " -a qubit" #Qubit
    #"quark"      = " -a quark" #Quark
    #"sib"        = " -a sib" #Sib
    #"skein"      = " -a skein" #Skein
    #"x11"        = " -a x11" #X11
    #"x12"        = " -a x12" #X12
    #"x13"        = " -a x13" #X13
    #"x14"        = " -a x14" #X14
}
#Commands from config file take precedence
if ($Miner_Config.Commands) { $Miner_Config.Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Commands | Add-Member $_ $($Miner_Config.Commands.$_) -Force } }

#CommonCommands from config file take precedence
if ($Miner_Config.CommonCommands) { $CommonCommands = $Miner_Config.CommonCommands }
else { $CommonCommands = "" }

$Devices = @($Devices | Where-Object Type -EQ "GPU" | Where-Object Vendor -EQ "NVIDIA")
$Devices | Select-Object Model -Unique | ForEach-Object { 
    $Miner_Device = @($Devices | Where-Object Model -EQ $_.Model)
    $Miner_Port = [UInt16]($Config.APIPort + ($Miner_Device | Select-Object -First 1 -ExpandProperty Id) + 1)

    $Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Algorithm_Norm = Get-Algorithm $_; $_ } | Where-Object { $Pools.$Algorithm_Norm.Protocol -eq "stratum+tcp" <#temp fix#> } | ForEach-Object { 
        $Miner_Name = (@($Name) + @($Miner_Device.Model | Sort-Object -unique | ForEach-Object { $Model = $_; "$(@($Miner_Device | Where-Object Model -eq $Model).Count)x$Model" }) | Select-Object) -join '-'

        #Get commands for active miner devices
        $Command = Get-CommandPerDevice -Command $Commands.$_ -ExcludeParameters @("a", "algo") -DeviceIDs $Miner_Device.Type_Vendor_Index

        Switch ($Algorithm_Norm) { 
            "C11"   { $WarmupTime = 60 }
            default { $WarmupTime = 30 }
        }

        [PSCustomObject]@{ 
            Name       = $Miner_Name
            DeviceName = $Miner_Device.Name
            Path       = $Path
            HashSHA256 = $HashSHA256
            Arguments  = ("$Command$CommonCommands -b 127.0.0.1:$($Miner_Port) -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass) -d $(($Miner_Device | ForEach-Object { '{0:x}' -f ($_.Type_Vendor_Index) }) -join ',')" -replace "\s+", " ").trim()
            HashRates  = [PSCustomObject]@{ $Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week }
            API        = "Ccminer"
            Port       = $Miner_port
            URI        = $Uri
            WarmupTime = $WarmupTime
        }
    }
}
