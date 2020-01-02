# vim: tabstop=4 noexpandtab

all: clean test verify

clean:
	ansible-playbook clean.yml
	
test:
	ansible-playbook test.yml

verify:
	ansible-playbook verify.yml

#
# Generally all targets in your Makefile which do not produce an output file 
# with the same name as the target name should be PHONY. This typically 
# includes all, install, clean, distclean, and so on.  
#
.PHONY: TODO

