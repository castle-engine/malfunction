default:
	@echo 'No default target in this Makefile'

# Simple install.
# You may as well symlink to /usr/local/share/malfunction, for system-wide install.
install:
	rm -f $(HOME)/.malfunction.data
	ln -s $(shell pwd) $(HOME)/.malfunction.data

# Run also "dircleaner . clean" here to really clean
.PHONY: clean
clean:
	rm -f malfunction malfunction.exe
