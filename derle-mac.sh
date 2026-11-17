#!/bin/bash
# Clawd.exe dosyasını macOS ya da Linux'ta derler (Windows'ta derle.bat yeterlidir).
#   ./derle-mac.sh <.NET Framework 4.8 başvuru kitaplıklarının klasörü>
# Kitaplıklar: nuget.org'daki Microsoft.NETFramework.ReferenceAssemblies.net48 paketinin
# build/.NETFramework/v4.8 klasörü. Derleyici: .NET SDK'nın içindeki Roslyn (csc.dll).
# DOTNET_ROOT ile SDK'nın yeri verilebilir; verilmezse yoldaki dotnet kullanılır.
# -langversion:5 verilir, çünkü Windows'un içindeki derleyici (derle.bat) yalnızca C# 5 tanır.
set -euo pipefail
cd "$(dirname "$0")"
REF="${1:?başvuru kitaplıklarının klasörünü ver}"
DOTNET="${DOTNET_ROOT:+$DOTNET_ROOT/}dotnet"
SDK="$("$DOTNET" --list-sdks | tail -1 | sed -E 's/^([^ ]+) \[(.*)\]$/\2\/\1/')"
"$DOTNET" "$SDK/Roslyn/bincore/csc.dll" -nologo -noconfig -nostdlib -langversion:5 -codepage:65001 \
    -target:winexe -optimize+ -platform:anycpu -warn:4 -out:Clawd.exe -win32icon:Clawd.ico \
    -r:"$REF/mscorlib.dll" -r:"$REF/System.dll" -r:"$REF/System.Core.dll" -r:"$REF/System.Drawing.dll" \
    -r:"$REF/System.Windows.Forms.dll" -r:"$REF/WindowsBase.dll" -r:"$REF/UIAutomationClient.dll" \
    -r:"$REF/UIAutomationTypes.dll" Clawd.cs
echo "Derlendi: Clawd.exe"
