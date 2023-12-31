using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject[]]$Devices
)

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\$($Name)\jce_cn_gpu_miner64.exe"
$HashSHA256 = "2D359EC26DE8C150341DC8665FB0F7C94909D1DE061A12ABE5C2EE391B5ADBF8"
$Uri = "https://github.com/jceminer/cn_gpu_miner/raw/master/jce_cn_gpu_miner.033b18.zip"
$ManualUri = "https://bitcointalk.org/index.php?topic=3281187.0"

$Miner_Config = Get-MinerConfig -Name $Name -Config $Config

$Commands = [PSCustomObject[]]@(
    #Unprofitable [PSCustomObject]@{ Algorithm = "Cryptonight";           MinMemGB = 2; Fee = 0.9; Command = " --variation 1" } #Original Cryptonight
    #Unprofitable [PSCustomObject]@{ Algorithm = "Cryptolight";           MinMemGB = 1; Fee = 0.9; Command = " --variation 2" } #Original Cryptolight
    [PSCustomObject]@{ Algorithm = "CryptonightV7";         MinMemGB = 2; Command = " --variation 3" } #CryptonightV1
    [PSCustomObject]@{ Algorithm = "CryptolightV7";         MinMemGB = 1; Command = " --variation 4" } #CryptolightV1
    [PSCustomObject]@{ Algorithm = "CryptonightHeavy";      MinMemGB = 4; Command = " --variation 5" } #CryptonightHeavy
    [PSCustomObject]@{ Algorithm = "CryptonightLiteIpbc";   MinMemGB = 1; Command = " --variation 6" } #CryptonightIPBC
    [PSCustomObject]@{ Algorithm = "CryptonightXtl";        MinMemGB = 2; Command = " --variation 7" } #CryptonightXtl
    [PSCustomObject]@{ Algorithm = "CryptonightXao";        MinMemGB = 2; Command = " --variation 8" } #CryptonightXao
    [PSCustomObject]@{ Algorithm = "CryptonightMarketCash"; MinMemGB = 2; Command = " --variation 9" } #CryptonightMarketCash
    [PSCustomObject]@{ Algorithm = "CryptonightRto";        MinMemGB = 2; Command = " --variation 10" } #CryptonightRto
    [PSCustomObject]@{ Algorithm = "CryptonightFast";       MinMemGB = 2; Command = " --variation 11" } #CryptonightFast
    [PSCustomObject]@{ Algorithm = "CryptonightHeavyHaven"; MinMemGB = 4; Command = " --variation 12" } #CryptonightHaven
    [PSCustomObject]@{ Algorithm = "CryptonightHeavyTube";  MinMemGB = 4; Command = " --variation 13" } #CryptonightHeavyTube
    [PSCustomObject]@{ Algorithm = "CryptonightRed";        MinMemGB = 1; Command = " --variation 14" } #CryptonightRed
    [PSCustomObject]@{ Algorithm = "CryptonightV8";         MinMemGB = 2; Command = " --variation 15" } #CryptonightV2
    #[PSCustomObject]@{ Algorithm = "_AUTO_";                MinMemGB = 2;   Command = " --variation 16" } #Pool-selected autoswitch, not supported by MPM
    [PSCustomObject]@{ Algorithm = "CryptonightDark";       MinMemGB = 1; Command = " --variation 17" } #CryptonightDark
    [PSCustomObject]@{ Algorithm = "CryptonightSwap";       MinMemGB = 2; Command = " --variation 18" } #CryptonightSwap
    [PSCustomObject]@{ Algorithm = "CryptonightuPlexa";     MinMemGB = 2; Command = " --variation 19" } #CryptonightUpx
    [PSCustomObject]@{ Algorithm = "CryptonightTurtle";     MinMemGB = 2; Command = " --variation 20" } #CryptonightTurtle
    [PSCustomObject]@{ Algorithm = "CryptonightFast2";      MinMemGB = 2; Command = " --variation 21" } #CryptonightFast2
    [PSCustomObject]@{ Algorithm = "CryptonightWaltzGraft"; MinMemGB = 2; Command = " --variation 22" } #CryptonightRwz
)
#Commands from config file take precedence
if ($Miner_Config.Commands) { $Miner_Config.Commands | ForEach-Object { $Algorithm = $_.Algorithm; $Commands = $Commands | Where-Object { $_.Algorithm -ne $Algorithm }; $Commands += $_ } }

#CommonCommands from config file take precedence
if ($Miner_Config.CommonCommands) { $CommonCommands = $Miner_Config.CommonCommands = $Miner_Config.CommonCommands }
else { $CommonCommands = " --stakjson --no-cpu --auto --no-warmup --low" } #Miner with low priority not to freeze your computer. Has a very small impact on performances. Recommended.

$Devices = @($Devices | Where-Object Type -EQ "GPU" | Where-Object Vendor -EQ "AMD")
$Devices | Select-Object Model -Unique | ForEach-Object { 
    $Device = @($Devices | Where-Object Model -EQ $_.Model)
    $Miner_Port = [UInt16]($Config.APIPort + ($Device | Select-Object -First 1 -ExpandProperty Id) + 1)
                
    $Commands | ForEach-Object { $Algorithm_Norm = $_.Algorithm; $_ } | Where-Object { $Pools.$Algorithm_Norm.Host } | ForEach-Object { 
        $Fee = $_.Fee
        $MinMemGB = $_.MinMemGB

        if ($Miner_Device = @($Device | Where-Object { ([math]::Round((10 * $_.OpenCL.GlobalMemSize / 1GB), 0) / 10) -ge $MinMemGB })) { 
            $Miner_Name = (@($Name) + @($Miner_Device.Model | Sort-Object -unique | ForEach-Object { $Model = $_; "$(@($Miner_Device | Where-Object Model -eq $Model).Count)x$Model" }) | Select-Object) -join '-'

            #Get commands for active miner devices
            $Command = Get-CommandPerDevice -Command $_.Command -DeviceIDs $Miner_Device.Type_Vendor_Index

            [PSCustomObject]@{ 
                Name       = $Miner_Name
                DeviceName = $Miner_Device.Name
                Path       = $Path
                HashSHA256 = $HashSHA256
                Arguments  = ("$Command$CommonCommands -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$(if ($Pools.$Algorithm_Norm.SSL) { " -ssl" })$(if ($Pools.$Algorithm_Norm.Name -like "NiceHash*") { " --nicehash" }) --mport $Miner_Port -g $(($Miner_Device | ForEach-Object { '{0:x}' -f ($_.Type_PlatformId_Index) }) -join ',')" -replace "\s+", " ").trim()
                HashRates  = [PSCustomObject]@{ $Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week }
                API        = "XmRig"
                Port       = $Miner_Port
                URI        = $Uri
                Fees       = [PSCustomObject]@{ $Algorithm_Norm = $Fee / 100 }
            }
        } 
    }
}
