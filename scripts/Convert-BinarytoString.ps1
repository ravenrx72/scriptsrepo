function Convert-BinarytoString {
    [CmdletBinding()] param (
      [string] $FilePath
    )
    try {
        $ByteArray = [System.IO.File]::ReadAllBytes($FilePath);
      }
      catch {
        throw "Failed to read file. Ensure you have permissions to file or path.";
      }
      if ($ByteArray){
          $Base64String = [System.Convert]::ToBase64String($ByteArray);

      }
      else {
        throw '$ByteArray is $null.';

      }
      Write-Output -InputObject $Base64String;
}
Convert-BinarytoString C:\obs\mimikatz.exe | Out-File C:\obs\mimi.txt
