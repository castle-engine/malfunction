default:
	@echo 'No default target in this Makefile'

# Simple install.
# You may as well symlink data to /usr/local/share/malfunction,
# for system-wide install.
install:
	rm -f $(HOME)/.local/share/malfunction
	ln -s $(shell pwd)/data $(HOME)/.local/share/malfunction

# Run also "dircleaner . clean" here to really clean
.PHONY: clean
clean:
	rm -f malfunction malfunction.exe
	rm -Rf malfunction.app

