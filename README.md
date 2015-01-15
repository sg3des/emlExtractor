#emlExtractor

Extractor email files in eml format.

    - extract header: subject, from, to, cc, date
    - email text in plain text and html formats
    - attachments

emlExtractor written in perl for linux.
	
##USAGE

	/path/to/emlExtractor [option] filename.eml [[option] filename.eml [option] filename.eml ...]

You can unpack multiple EML files in one line, just write them separated by a space.
For each file eml, will be created directory kind filename_eml with same path, where will be unpacked files.

You may set output directory with option:
  -o  --output      set output directory
  -c                set filename for html and text message as the same of filename input eml
  -v  --overwrite   overwrite exists files

set output directory for each file, or one at all, or any other way.

	eml.header - information header of email message
	*.text  - text message in plain text format
	*.html  - text message in html format


##PREMISE

eml files this is format email messages, BUT not all server form its same.
I have not found any unpacker EML-files, which would correctly cope with all this "exotic", the biggest surprise - attachments in binary view ... 

##INFORMATION

in some cases, in eml files encountered winmail.dat that contains attachments and text. I did not write my "bike" for this case, since this task perfectly copes application tnef.


>uses several CPAN modules for execution perl script(emlExtractor.pl) will probably need: MIME::QuotedPrint::Perl
for compiling an executable file - PAR::Packer
