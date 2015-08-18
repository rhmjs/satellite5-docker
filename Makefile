OUTPUT = satellite5-docker.pdf satellite5-docker.html satellite5-docker.txt

all: ${OUTPUT}

clean:
	rm -f ${OUTPUT}
	
git-ready:
	@${MAKE} -s clean
	@${MAKE} -s all
	@${MAKE} -s clean
	git status	
	
%.pdf: README.md
	pandoc $^ -o $@

%.html: README.md
	pandoc $^ -o $@

%.txt: README.md
	pandoc $^ -o $@
