$ErrorActionPreference = "Stop"

# Don't display progressbars when doing Invoke-WebRequest and similar.
# That would cause the command to fail, because in the CircleCI environment
# one can't modify the display.
# "Win32 internal error “Access is denied” 0x5 occurred while reading the console output buffer. Contact Microsoft Customer Support Services."
$progressPreference = 'silentlyContinue'

function CheckLastExitCode {
    if ($LastExitCode -ne 0) {
        $msg = @"
Program failed with: $LastExitCode
Callstack: $(Get-PSCallStack | Out-String)
"@
        throw $msg
    }
}


# Install Perl

mkdir download
mkdir strawberry
Invoke-WebRequest http://strawberryperl.com/download/5.30.0.1/strawberry-perl-5.30.0.1-64bit.zip -OutFile download/strawberry-perl-5.30.0.1-64bit.zip
Expand-Archive -Path download/strawberry-perl-5.30.0.1-64bit.zip -DestinationPath strawberry
strawberry\relocation.pl.bat
$Env:PATH = (Join-Path -Path $repoPath -ChildPath "\strawberry\perl\bin") + ";" + (Join-Path -Path $repoPath -ChildPath "\strawberry\perl\site\bin") + ";" + (Join-Path -Path $repoPath -ChildPath "\strawberry\c\bin") + ";$Env:PATH"


# Build Rakudo

perl Configure.pl --gen-moar --gen-nqp --backends=moar --relocatable
CheckLastExitCode
nmake install
CheckLastExitCode


# Test the build

nmake test
CheckLastExitCode


# Build Zef

git clone https://github.com/ugexe/zef.git
CheckLastExitCode
cd zef
..\install\bin\raku.exe -I. bin\zef install .
CheckLastExitCode


# Prepare the package

cp -r "tools\build\binary-release\Windows\*" install
cp LICENSE install

$version = Get-Content -Path .\VERSION -Raw
$version = $version.Trim()
mv install rakudo-$version

Compress-Archive -Path rakudo-$version -DestinationPath rakudo-win.zip

