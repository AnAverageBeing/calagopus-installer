# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Vagrantfile - integration test boxes for the Calagopus Installer.
#
# Each box mirrors a supported OS. `vagrant up` boots all of them; the project
# directory is mounted at /vagrant so you can run the installer inside the VM
# with `sudo /vagrant/src/installer.sh`.

COMMON_PROVISION = <<~PROVISION
  echo "== Installing bats for tests =="
  apt-get update -y >/dev/null 2>&1 || dnf install -y bats >/dev/null 2>&1 || true
  echo "== Ready: run  sudo /vagrant/src/installer.sh --dry-run --non-interactive --yes --action install_full --target full =="
PROVISION

Vagrant.configure("2") do |config|
	config.vm.provider "virtualbox" do |vb|
		vb.memory = 2048
		vb.cpus = 2
	end

	# Ubuntu LTS
	config.vm.define "ubuntu_jammy" do |b|
		b.vm.box = "ubuntu/jammy64"
		b.vm.provision "shell", inline: COMMON_PROVISION
	end
	config.vm.define "ubuntu_noble" do |b|
		b.vm.box = "ubuntu/noble64"
		b.vm.provision "shell", inline: COMMON_PROVISION
	end

	# Debian
	config.vm.define "debian_bookworm" do |b|
		b.vm.box = "debian/bookworm64"
		b.vm.provision "shell", inline: COMMON_PROVISION
	end
	config.vm.define "debian_trixie" do |b|
		b.vm.box = "debian/trixie64"
		b.vm.provision "shell", inline: COMMON_PROVISION
	end

	# RHEL family
	config.vm.define "rockylinux_9" do |b|
		b.vm.box = "rockylinux/9"
	end
	config.vm.define "almalinux_9" do |b|
		b.vm.box = "almalinux/9"
	end
	config.vm.define "fedora_40" do |b|
		b.vm.box = "fedora/40-cloud-base"
	end

	# Arch
	config.vm.define "archlinux" do |b|
		b.vm.box = "archlinux/archlinux"
	end
end
