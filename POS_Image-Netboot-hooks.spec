%define version 10.1.1
%define pkg POS_Image-Netboot-hooks
%define _topdir %(echo $PWD)/
%define prefix /lib/kiwi/hooks
%define _unpackaged_files_terminate_build 0

Name: %{pkg}
Version: %{version}
Release: 1
Summary: Custom SLEPOS netboot hooks for Office Depot
Vendor: Office Depot
Group: RetailEngineering
License: GPL
Source0: %{pkg}.tgz
BuildRoot: %{_tmppath}/%{pkg}

%description
Standard netboot hooks for SLEPOS, with custom additions for Office Depot.

%prep
%setup -q -n %{pkg}

%build

%install
%{__mkdir_p} %{buildroot}%{prefix}
install --directory %{buildroot}%{prefix}
cp -a * %{buildroot}

%post

%files
%defattr(-,root,root)
%dir %{prefix} 

%{prefix}/*

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Fri Nov 7 2019 Tristan Evans <tristan.evans@officedepot.com> 10.1.0
-Adding logging to feed into Splunk for analysis.
