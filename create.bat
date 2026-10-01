set CEF_ENABLE_ARM64=1
set CEF_ENABLE_ARM64EC=1
set GN_DEFINES=is_component_build=false v8_enable_pointer_compression=false
set GN_ARGUMENTS=--ide=vs2022 --sln=cef --filters=//cef/*
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
set GYP_MSVS_VERSION=2022
call cef_create_projects.bat