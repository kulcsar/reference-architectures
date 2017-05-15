[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True)]
  [string]$driveLetter,

  [Parameter(Mandatory=$True)]
  [string]$fileShareUri,

  [Parameter(Mandatory=$True)]
  [string]$storageAccountName,

  [Parameter(Mandatory=$True)]
  [string]$storageAccountKey

)

$fileShareName = $fileShareUri.Replace("https://", "")
$fileShareName = $fileShareName.Replace("/", "\")

$cmd = "net use ${driveLetter}: \\$fileShareName /USER:AZURE\$storageAccountName $storageAccountKey /persistent:Yes"
Invoke-Expression -Command $cmd
