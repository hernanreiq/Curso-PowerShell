Get-Item -Path 'C:\Users\Ghost\Desktop\*' | Where {$_.LastWriteTime -lt (Get-Date).AddDays(-3)}
// Si le agrega "| Remove-Item" al final, se borraran los que cumplan la condicion