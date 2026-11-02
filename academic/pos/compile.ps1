# Script de Compilação do TCC em Typst
# Certifique-se de ter o Typst instalado (https://typst.app/docs/installation/)
# Para compilar, basta rodar este script.

$MainFile = "main.typ"
$OutputFile = "TCC_Pos.pdf"

Write-Host "Iniciando compilação do Typst..." -ForegroundColor Cyan

# Verifica se o typst está instalado
if (Get-Command "typst" -ErrorAction SilentlyContinue) {
    # typst compile main.typ TCC_Pos.pdf
    typst compile $MainFile $OutputFile
    
    if ($?) {
        Write-Host "✅ Compilação concluída com sucesso! Arquivo gerado: $OutputFile" -ForegroundColor Green
    } else {
        Write-Host "❌ Erro ao compilar o documento." -ForegroundColor Red
    }
} else {
    Write-Host "❌ O comando 'typst' não foi encontrado." -ForegroundColor Red
    Write-Host "Por favor, instale o Typst localmente via Winget:" -ForegroundColor Yellow
    Write-Host "winget install --id Typst.Typst" -ForegroundColor Yellow
}
