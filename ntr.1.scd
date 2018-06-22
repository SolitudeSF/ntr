ntr(1)

# NAME
ntr - render configuration files based on specified context

# SYNOPSYS
_ntr_ [--in:_input-file_] [--out:_output-file_] [_context-file_]

# DESCRIPTION
lmao


# OPTIONS
*-i:*_file_*, --in:*_file_
	Add input file

*-o:*_file_*, --outfile:*_file_
	Add output file. _--_ outputs file to stdout.

*-I:*_file_*, --inplace:*_file_
	Add input file and render it in-place

*-p:*_file_*, --profile:*_file_
	Specify profile file

*--noDefaultProfile, --ndp*
	Disable default profile

*--NoDefaultContext, --ndc*
	Disable default context

*--NoDefaultFinisher, --ndf*
	Disable default finisher

*--override:*_key_*:*_value_
	Add or override existing context

*--backup*
	Backup if output file exists

*-e, --empty*
	Don't abort on empty context

*-E*
	Force empty context (don't use specified context files, default context file or manual overrides)

*-d*
	Only use file from ntrDirectory

*-D*
	Never use files from ntrDirectory

*-h, --help*
	Print help message

*-v, --version*
	Show version information


# FILES

${XDG\_CONFIG\_HOME}/ntr:
	- contexts
	- templates
	- profiles
	- finishers


# EXAMPLES
ntr mytheme
	render files specified in default profile using _"mytheme"_ context and run corresponding finishers if present

ntr -i:templ -o:res
	render file _"templ"_ into file _"res"_ using default context
