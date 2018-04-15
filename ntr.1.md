% ntr(1)
% SolitudeSF
% April 14, 2018

# NAME

ntr - render configuration files based on specified context

# SYNOPSYS

*ntr* [\--in:*input-file*] [\--out:*output-file*] [*context-file*]

# DESCRIPTION

lmao


# OPTIONS

-i:*file*, \--in:*file*,
:	Add input file

-o:*file*, \--out*file*,
:	Add output file. **\--** outputs file to stdout.

-I:*file*, \--inplace:*file*,
:	Add input file and render it in-place

-p:*file*, \--profile:*file*,
:	Specify profile file

\--noDefaultProfile, \--ndp,
:	Disable default profile

\--NoDefaultContext, \--ndc,
:	Disable default context

\--NoDefaultFinisher, \--ndf,
:	Disable default finisher

\--override:*key*:*value*,
:	Add or override existing context

\--backup,
:	Backup if output file exists

-e, \--empty,
:	Don't abort on empty context

-E,
:	Force empty context (don't use specified context files, default context file or manual overrides)

-d,
:	Only use file from ntrDirectory

-D,
:	Never use files from ntrDirectory

-h, \--help,
:	Print help message

-v, \--version,
:	Show version information


# FILES

ntrDirectory


# EXAMPLES

ntr mytheme
:	render files specified in default profile using *"mytheme"* context and run corresponding finishers if present

ntr -i:templ -o:res
:	render file *"templ"* into file *"res"* using default context
