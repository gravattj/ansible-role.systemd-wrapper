# vim: tabstop=4 noexpandtab

install:
	sudo mkdir -p /etc/ansible/roles
	sudo rsync -av systemd_wrapper/ /etc/ansible/roles/systemd_wrapper

test:
	cd systemd_wrapper/tests && make all

#
# Generally all targets in your Makefile which do not produce an output file 
# with the same name as the target name should be PHONY. This typically 
# includes all, install, clean, distclean, and so on.  
#
.PHONY: TODO

