# vim: tabstop=4 noexpandtab

install:
	sudo mkdir -p /etc/ansible/roles
	sudo rsync -av systemd_wrapper.gravattj/ /etc/ansible/roles/systemd_wrapper.gravattj

test:
	cd systemd_wrapper.gravattj/tests && make all

#
# Generally all targets in your Makefile which do not produce an output file 
# with the same name as the target name should be PHONY. This typically 
# includes all, install, clean, distclean, and so on.  
#
.PHONY: TODO

