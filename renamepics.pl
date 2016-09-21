################################################################################

=head1 NAME

renamepics - provides services to rename (and renumber) picture and movie
             files in a given directory

=head1 SYNOPSIS

renamepics [?|-h|--help] [-m|--man]
           [-t|--test]
           [-s|--sortby=<name|num|time>] [-b|--basename=<base filename>] <dir>

=item B<renamepics --help>

=item B<renamepics --test --sortby=name --basedir=Beach_Party /pics/Beach_Party>

=item B<renamepics -t -s name -b Beach_Party /pics/Beach_Party>

=head1 OPTIONS

=over 8

=item B<-b, --basename=<basename>>

Determines the base file name after the files have been renamed (e.g., 
something.jpg could become "Beach_Party_0001.jpg" if the command is called with 
the following option: --basname=Beach_Party).

=item B<-s, --sortby=<num|name|time>>

Sorts the files in ascending order according to the number (num) in their
existing filenames (e.g., something-2.jpg), according to the entire alphanumeric 
filename (name), or according to when the photo/movie was taken (time).  This
affects the numeric portion of the resulting filename and how the files will 
sort alphanumerically after they have been renamed.

=item B<-t, --test>

No image or movie files are renamed; this flag executes the command in test
mode.  A list of files that would be renamed are reported on screen and in the
log files.

=item B<-?, -h, --help>

Displays a brief Help message.

=item B<-m, --man>

Displays the Manual page.

=back

=head1 DESCRIPTION

This program is designed to ensure all picture and movie files in a given
collection are named consistently, and are displayed in the desired order
when sorted alphanumerically.

Users would typically sort and rename files in Picasa (Edit->Select All;
File->Rename).  If the user enters "Something" as the desired filename,
Picasa renames the selected files as:

   Something.JPG
   Something-1.JPG
   Something-2.JPG
   Something-3.JPG

When the file count exceeds 10, these files will not be displayed in a
logical order when sorted alphanumerically.  (For example,
Something-10 would be displayed before Something-9).  There are also
times when users delete files resulting in missing numbers.

That is where this script comes into play.  It renames files (after the
Picasa rename) to ensure they are logically ordered when sorted
alphanumerically.  If no command line options are specified, it will
rename the files specified above to:

   Something_0000.jpg
   Something_0001.jpg
   Something_0002.jpg
   Something_0003.jpg

assuming all files in the specified directory follow the same naming/
numbering convention.  The program will make no changes, however, if the
directory contains:

   1. No files with the following extensions: .jpg, .wmv (in any case).
      All other file types are ignored.

   2. Multiple files with different and/or unrecognized naming/numbering
      conventions (e.g., something-1.jpg, something_else-2.jpg).  If the
      -f option is specified, the script assumes that all files in the
      directory follow the naming/numbering convention of the first file.
      Files that deviate from this convention are not renamed.

If the specified directory contains the following files, for example, the
-n flag will reNumber the files sequentially.  Note the script determines
standard naming/numbering convention in a case insensitive manner:

   Something_Else_0001.jpg => Something_Else_0001.jpg
   Something_else_0004.Jpg => Something_else_0002.jpg
   SomeThing_Else_0007.JPG => SomeThing_Else_0003.jpg
   SOMETHING_ELSE_0010.jpg => SOMETHING_ELSE_0004.jpg

=head1 REVISION HISTORY

Alazhar Shamshuddin   2008-04-01   Initial version

=head1 COPYRIGHT

(c) Copyright Alazhar Shamshuddin, 2008, All Rights Reserved.

=cut

################################################################################

use strict;
use warnings;

use Data::Dumper;                # For debugging data structures.
use File::Copy;                  # For renaming (copying) files.
use File::Spec;                  # For managing file paths.
use Getopt::Long;                # For command-line options processing.
use Image::ExifTool qw(:Public); # For processing EXIF data.
use Log::Log4perl;               # For logging.
use Pod::Usage;                  # For printing usage clause and man page.

################################################################################
# Global Variables
################################################################################
use constant TRUE  => 1;
use constant FALSE => 0;

my $gMaxSeqNumDigits     = 4;
my $gRenameReporFilename = '/home/Alazhar/.local/tmp/rename_report.txt';
my @gFileTypes           = ('jpg', 'wmv', 'mp4');

my $gLogger              = undef;
my %gCmds                = ();
my %gRenameReport        = ();

################################################################################
# Subroutines
#
#    All subroutinese are organized alphanumerically in the following
#    categories:
#
#       - Main
#            - main
#       - Intialization
#            - initLogger
#            - processCmdLineArgs
#       - Renaming
#            - generateNewName
#            - processDir
#            - renameFiles
#            - sortFiles
#            - sortFilesByNum
#            - sortFilesByTime
#        - Reporting
#            - generateRenameReport
#            - getStatusCounts
################################################################################

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main();
sub main
{
   initLogger(0, \$gLogger);
   $gLogger->info("*** Executing $0. ***");

   processCmdLineArgs(\%gCmds);
   
   my $dirName = File::Spec->canonpath($gCmds{directory});
   $dirName = File::Spec->rel2abs($dirName);
   processDir($dirName);

   $gLogger->info("*** Completed executing $0. ***");
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Intialization Subroutines
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#-------------------------------------------------------------------------------
# Initializes the logging functionality.
#
# \param $_[0] [in]  The log configuration filename.
# \param $_[1] [out] A reference to a logger.
#
# \return None.
#-------------------------------------------------------------------------------
sub initLogger
{
   # Initialize the logger.
   my $logConfigFile = $_[0];
   my $logger_sr     = $_[1];

   if (-r $logConfigFile)
   {
      Log::Log4perl->init($logConfigFile);
   }
   else
   {
      # Configuration in a string.
      my $logConfigString = q(
         log4perl.rootLogger=TRACE, FILE, SCREEN

         # Filter to match WARN messages
         #log4perl.filter.MatchInfo = Log::Log4perl::Filter::LevelMatch
         #log4perl.filter.MatchInfo.LevelToMatch = WARN
         #log4perl.filter.MatchInfo.AcceptOnMatch = true

         # Filter to match range from WARN up 
         log4perl.filter.MatchWarnUp = Log::Log4perl::Filter::LevelRange 
         log4perl.filter.MatchWarnUp.LevelMin = WARN 
         #log4perl.filter.MatchWarnUp.LevelMax = FATAL 
         log4perl.filter.MatchWarnUp.AcceptOnMatch = true         

         #----------------------------------------------------------------------
         # For writing log messages to a file in the following format:
         #
         #   (%d)                (%r)  (%p)  (%l)                     (%m%n)
         #   2008/03/26 15:16:14 [127] ERROR main::fnc file.pl (599): Message.
         #----------------------------------------------------------------------
         log4perl.appender.FILE          = Log::Log4perl::Appender::File
         log4perl.appender.FILE.filename = /home/Alazhar/.local/tmp/renamepics.log
         log4perl.appender.FILE.mode     = clobber
         log4perl.appender.FILE.layout   = PatternLayout
         log4perl.appender.FILE.layout.ConversionPattern = %d [%r] %p %l: %m%n

         #----------------------------------------------------------------------
         # For writing log messages to the screen in the following format:
         #
         #   (%r)  (%p)  (%l)                     (%m%n)
         #   [127] ERROR main::fnc file.pl (599): Message.
         #----------------------------------------------------------------------
         log4perl.appender.SCREEN        = Log::Log4perl::Appender::Screen
         log4perl.appender.SCREEN.stderr = 0
         log4perl.appender.SCREEN.layout = PatternLayout
         log4perl.appender.SCREEN.layout.ConversionPattern = [%r] %p %l: %m%n
         log4perl.appender.SCREEN.Filter = MatchWarnUp
         );

      Log::Log4perl::init( \$logConfigString );
   }

   $$logger_sr = Log::Log4perl->get_logger("$0");
   die "FATAL: Could not initialize the logger." unless $$logger_sr;
}


#-------------------------------------------------------------------------------
# Processes command line arguments, and informs the user of invalid
# parameters.  All command-line options/values are inserted in the global
# commands hash (gCmds).
#
# This subroutine also displays the usage clause if there are any errors,
# or the help or manual pages if the user explicitly requests them.
# Displaying the usage clause, help page and manual pages via pod2usage
# automatically terminates this script.
# 
# \return None.
#-------------------------------------------------------------------------------
sub processCmdLineArgs
{
   Pod::Usage::pod2usage(1) unless
      Getopt::Long::GetOptions(
        "basename|b=s" => \$gCmds{basename},
        "sortby|s=s"   => \$gCmds{sortby},
        "test|t"       => \$gCmds{test},
        "help|?"       => \$gCmds{help},
        "man|m"        => \$gCmds{man}
      );

   # We expect no remaining commands/options on the command line after we
   # retrieve the directory.  @ARGV should be empty after the following line.
   $gCmds{directory} = shift(@ARGV);

   Pod::Usage::pod2usage(1) if $gCmds{help};
   Pod::Usage::pod2usage( -verbose => 2 ) if $gCmds{man};

   # Ensure the sortby option is specified.
   if (!defined($gCmds{sortby}))
   {
      my $msg = "A sortby option of name, num or time must be specified.";

      $gLogger->info($msg);
      print(STDERR "$msg\n\n");

      Pod::Usage::pod2usage(1);       
   }   

   # Ensure the sortby option is set to name, num or time.
   if ($gCmds{sortby} && $gCmds{sortby} !~ m!^(name|num|time)$!) 
   {
      my $msg = "Invalid sortby option '$gCmds{sortby}'.  It must be one of " .
                "name, num or time.";

      $gLogger->info($msg);
      print(STDERR "$msg\n\n");

      Pod::Usage::pod2usage(1); 
   }

   # Ensure the base name option is specified.
   if (!defined($gCmds{basename}))
   {
      my $msg = "A base filename must be specified.";

      $gLogger->info($msg);
      print(STDERR "$msg\n\n");

      Pod::Usage::pod2usage(1);       
   } 

   # Ensure the specified base filename follows our naming convention.
   if ($gCmds{basename} && $gCmds{basename} !~ m!^[A-Z][A-Za-z0-9_]*$!) 
   {
      my $msg = "Invalid base filename '$gCmds{basename}'.  It must start " .
                "with a capital letter and only contain alphanumeric " .
                "characters and underscores.";

      $gLogger->info($msg);
      print(STDERR "$msg\n\n");

      Pod::Usage::pod2usage(1); 
   }   

   # Ensure there are no more command line parameters to process.  Currently
   # we do not allow the user to process more than one directory at a time.
   if (scalar(@ARGV) > 0) 
   {
      my $dirs = join(',', @ARGV);
      my $msg = "Invalid command line entries: '$dirs'.  $0 can only " .
                "process one directory at a time.";

      $gLogger->info($msg);
      print(STDERR "$msg\n\n");

      Pod::Usage::pod2usage(1);     
   }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Renaming Subroutines
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#-------------------------------------------------------------------------------
# Adds a key-value pair to the specified hash reference.  The key is a date time
# value extracted from the file's EXIF data, and the value is the base
# filename.
#
# Note: This is a helper method to the SortFilesByTime function.  If there is a 
# a date time key collision, this method increments the date time value as 
# follows until a unique value is found:
#
#   2016:09:14 17:19:07.0 --> 2016:09:14 17:19:07.1
#
# \param $_[0] [in_out] A reference to a hash of filenames keyed on the date
#                       time EXIF value for each file.
# \param $_[1] [in]     A date time key to insert in the above hash.
# \param $_[1] [in]     The filename (value) associated with the above key.
#
# \return None.
#-------------------------------------------------------------------------------
sub AddFileDateTimeEntry
{
   my $fileDateTimes_hr = $_[0];
   my $fileDateTime     = $_[1];
   my $fileName         = $_[2];
 
   if (exists($fileDateTimes_hr->{$fileDateTime})) 
   {
      # This date time value already exists.  Hence increment the trailing
      # digit until a unique value is found.
      $fileDateTime =~ s!\.(\d+)$!\.!;
      $fileDateTime = $fileDateTime . ($1 + 1);
      AddFileDateTimeEntry($fileDateTimes_hr, $fileDateTime, $fileName);
   }
   else
   {
      $fileDateTimes_hr->{$fileDateTime} = $fileName;
   }
}

#-------------------------------------------------------------------------------
# Adds a key-value pair to the specified hash reference.  The key is a numerical
# value extracted from the filename itself, and the value is the base
# filename.
#
# Note: This is a helper method to the SortFilesByNum function.  If the key 
# already exists, it is incremented until a unique value is found.  (The only 
# time a numerical key will exist is when you have the same filename in a folder
# with different file types or extensions.  For example:
#
#   Something-1.jpg
#   Something-1.wmv
#
# \param $_[0] [in_out] A reference to a hash of filenames keyed on the number
#                       in each filename.
# \param $_[1] [in]     A numerical key to insert in the above hash.
# \param $_[1] [in]     The filename (value) associated with the above key.
#
# \return None.
#-------------------------------------------------------------------------------
sub AddFileNumEntry
{
   my $fileNums_hr = $_[0];
   my $fileNum     = $_[1];
   my $fileName    = $_[2];

   if (exists($fileNums_hr->{$fileNum}))
   {
      # This file number value already exists.  Hence increment it until a 
      # unique value is found.      
      AddFileNumEntry($fileNums_hr, $fileNum + 1, $fileName);
   }
   else
   {
      $fileNums_hr->{$fileNum} = $fileName;
   }
}

#-------------------------------------------------------------------------------
# Generates a new filename based on the specified basename, sequence number
# or sort order, and the file type or extension.  For example:
#
#    Something_0001.jpg
#    |---1---| |-2| |3|
# 
# Where:
#    1 = Basename
#    2 = Sequence number
#    3 = File type or extension
#
# Note the following:
#    1. This method will always generate filenames with lowercased 
#       extensions.
#   
#    2. If sequence number contains more digits than the maximum allowable 
#       digits, the maximum will be ignored.  If it contains fewer digits,
#       if will be left-padded with zeros.
# 
# \param $_[0] [in] The base filename.
# \param $_[1] [in] The sequence number.
# \param $_[2] [in] The maximum allowable digits in the sequence number.
# \param $_[3] [in] The file type or extension.
#
# \return The new filename.
#-------------------------------------------------------------------------------
sub generateNewName
{
   my $baseName        = $_[0];
   my $seqNum          = $_[1];
   my $maxSeqNumLength = $_[2];
   my $extension       = lc($_[3]);

   if (length($seqNum) > $maxSeqNumLength) 
   {
      $gLogger->logdie("File sequence number ($seqNum) is longer than the " .
                       "maximum allowable sequence number ($maxSeqNumLength " .
                       "digits).");
   }

   my $seqNumFormat = '%0' . $maxSeqNumLength . 'd';

   my $fileName = $baseName . 
                  '_' . 
                  sprintf($seqNumFormat, $seqNum) . 
                  '.' .
                  $extension;

   return $fileName;
}

#-------------------------------------------------------------------------------
# Processes the specified directory of files.
#
# \param $_[0] [in] The directory to be processed.
#
# \return None.
#-------------------------------------------------------------------------------
sub processDir
{
   my $dirName = $_[0];

   opendir(my $dirName_fh, $dirName) or
      $gLogger->logdie("Cannot opendir '$dirName': $!");

   $gLogger->info("Processing '$dirName'.");

   my %requiredFiles = ();
   my $fileTypes     = join("|", @gFileTypes);

   # Fetch the files we need to process into the requiredFiles hash.  We
   # only process the files in the current directory with specific extensions
   # or file types. Subdirectories and all other file types are ignored.
   foreach my $item (sort readdir($dirName_fh))
   {
      # Rename $item to include relative path information.
      my $itemWithPath = File::Spec->catfile($dirName, $item);
      $itemWithPath = File::Spec->canonpath($itemWithPath);

      if (-f $itemWithPath && $item =~ m!.+\.($fileTypes)$!i)
      {
         $requiredFiles{$item} = { curr_abs_path => $itemWithPath,
                                   directory => $dirName,
                                   status => 'Unprocessed'
                                 }
      }

      $gLogger->info("Ignored item '$itemWithPath'.");
   }
   closedir($dirName_fh);

   # Sort the files by establishing sequence number for each entry in the
   # requiredFiles hash.
   my $isSortSuccessful = sortFiles(\%requiredFiles);

   # Rename the files only if we could establish the correct sorting order for
   # the required files.
   if ($isSortSuccessful == FALSE) 
   {
      $gLogger->error("Could not sort files.  Hence we could not rename " .
                      "the files.");
   }
   else
   {
      renameFiles(\%requiredFiles);
   }

   print(generateRenameReport(\%requiredFiles, 
                              $dirName, 
                              $gRenameReporFilename));
}

#-------------------------------------------------------------------------------
# Renames the files in the specified hash.
#
#   'Something.jpg'     =>  { 'curr_abs_path' => '/pics/Something.jpg',
#                             'seq_num' => 2
#                           },
#   'Something.wmv'     =>  { 'curr_abs_path' => '/pics/Something.wmv', 
#                             'seq_num' => 1
#                           },                               
#   'Something-001.jpg' =>  { 'curr_abs_path' => '/pics/Something-001.jpg',
#                             'seq_num' => 3
#                           },
#   'Something-003.jpg'  => { 'curr_abs_path' => '/pics/Something-003.jpg',
#                             'seq_num' => 4
#                           },
#
# \param $_[0] [in_out] A reference to a hash of filenames keyed on the base 
#                       filename that need to be renamed.
# \param $_[1] [in-out] A reference to rename record hash for the
#                       directory being processed.
#
# \return None.
#-------------------------------------------------------------------------------
sub renameFiles
{
   my $files_hr = $_[0];

   my $fileTypes = join("|", @gFileTypes);
   my $fileType  = undef;

   my %oldFileNames = ();
   my %newFileNames = ();

   foreach my $file (keys(%$files_hr))
   {
      $file =~ m!.+\.($fileTypes)$!i;
      $fileType = $1;

      $files_hr->{$file}->{new_name} = 
         generateNewName($gCmds{basename}, 
                         $files_hr->{$file}->{seq_num},
                         $gMaxSeqNumDigits,
                         $fileType);

      $files_hr->{$file}->{new_abs_path} = 
         File::Spec->catfile($files_hr->{$file}->{directory}, 
                             $files_hr->{$file}->{new_name});

      $oldFileNames{$file} = $files_hr->{$file}->{new_name};

      if ($newFileNames{$files_hr->{$file}->{new_name}} ||
          $oldFileNames{$files_hr->{$file}->{new_name}})
      {
         $files_hr->{$file}->{status} = 'Error';

         $gLogger->error("Cannot rename '$file' to " .
                         "an existing file '$files_hr->{$file}->{new_name}'.");
         return;
      }

      $files_hr->{$file}->{status} = 'Ready'
   }

   if (!$gCmds{test}) 
   {
      foreach my $file (keys(%$files_hr))
      {      
         # Rename the file.
         move($files_hr->{$file}->{curr_abs_path}, 
              $files_hr->{$file}->{new_abs_path}) or
            $gLogger->error("Could not rename file '$file' to ".
                            "'$files_hr->{$file}->{new_abs_path}': $!");

         $gLogger->info("Renamed '$file' to ".
                        "'$files_hr->{$file}->{new_abs_path}'.");

         # Update the files status for reporting purposes.
         $files_hr->{$file}->{status} = 'Renamed';
      }
   }
}

#-------------------------------------------------------------------------------
# Sorts the specified files, as specified on the command line, according to
# their names, embedded numbers in their filenames, or their creation date.  
# This function modifies the specified hash to include a sort order or 
# sequence number as shown below:
#
#    {
#       'Something.jpg'   => { 'oldPath' => '/pics/test/Something.jpg',
#                              'seq_num' => 1,
#                            },
#       'Something-1.jpg' => { 'oldPath' => '/pics/test/Something-2.jpg,
#                              'seq_num' => 2
#                            }
#    }
#
# \param $_[0] [in_out] A reference to a hash of filenames keyed on the current 
#                       filename that need to be sorted.
#
# \return TRUE if the files could be sorted and a sequence number is assigned 
#         to each file in the reference hash; FALSE otherwise.
#-------------------------------------------------------------------------------
sub sortFiles
{
   my $files_hr = $_[0];

   my $seqNum = undef;
   my $status = FALSE;

   if ($gCmds{sortby} eq 'name') 
   {
      $seqNum = 1;

      foreach my $file (sort {lc $a cmp lc $b} keys(%$files_hr))
      {
         $files_hr->{$file}->{seq_num} = $seqNum;
         $seqNum++;
      }

      $status = TRUE;
   }
   elsif ($gCmds{sortby} eq 'num') 
   {
      $status = sortFilesByNum($files_hr, \$seqNum);
   }
   elsif ($gCmds{sortby} eq 'time') 
   {
      $status = sortFilesByTime($files_hr, \$seqNum);
   }
   else {
      $gLogger->logdie("Invalid sortby parameter '$gCmds{sortby}'.")
   }

   if (length($seqNum) > $gMaxSeqNumDigits)
   {
      $gLogger->error("The last sequence number ('$seqNum') for the sorted " .
                      "files is longer than the maximum allowable sequence " .
                      "number ($gMaxSeqNumDigits digit(s)).  Files cannot " .
                      "be named correctly.  Modify the script to " .
                      "extend the maximum before trying again.");
      return FALSE;
   }

   return $status;
}

#-------------------------------------------------------------------------------
# Sorts the files by the trailing number in their filenames in ascending order.
# The base filenames (minus the number) must be identical for all files that 
# need to to be sorted.
#
# Please refer to the following examples:
#
#    P.jpg             --> seq_num = 1
#    P111084.jpg       --> seq_num = 2
#    P111088.jpg       --> seq_num = 3 
# 
#    Something.jpg     --> seq_num = 1 
#    Something-0.jpg   --> seq_num = 2 
#    Something-02.jpg  --> seq_num = 3 
#
#    Foo-1.jpg         --> Cannot be sorted
#    Bar-2.jpg         --> Cannot be sorted
#
# \param $_[0] [in_out] A reference to a hash of filenames keyed on the base 
#                       filename.
# \param $_[1] [in_out] A reference to a scalar that will represent the
#                       maximum sequence number once the files are sorted.
#
# \return TRUE if the files could be sorted and a sequence number is assigned 
#         to each file in the reference hash; FALSE otherwise.
#-------------------------------------------------------------------------------
sub sortFilesByNum
{
   my $files_hr  = $_[0];
   my $seqNum_sr = $_[1];

   # Current and previous matches store the base filenames, excluding
   # the file extension and period. They are used to verify whether
   # all the specified files follow the same naming/numbering convention.
   my $prevMatch = undef;
   my $currMatch = undef;
   my $fileNum   = undef;

   # A temporary hash to store the filenames we process (values) keyed
   # on the number in those base filenames.  This allows us to numerically
   # sort the keys to determine the sequence number or sort order for each file.
   my %fileNums = ();

   foreach my $file (sort {lc $a cmp lc $b} keys(%$files_hr))
   {
      if ($file =~ m!^([a-z0-9_ ]+?)([ _-]?)(\d*)\.[a-z]+$!i)
      {
         # The current match includes only the base filename, minus
         # the extension for a case-insensitive comparison.
         $currMatch = lc($1);
         $fileNum = $3;

         # If the filename contains no trailing numbers we assume it's supposed
         # to be the first file in the set (as this is how Google's photo
         # management software, Picasa, renames its files).
         if ($fileNum eq '') 
         {
            $fileNum = 0;
         }
      }
      else 
      {
         # The files don't follow an expected naming pattern.  Hence we stop
         # sorting these files by number.
         $gLogger->error("'$file' does not adhere to established naming " .
                         "conventions. Hence we cannot sort this folder by ". 
                         "number.");
         return FALSE;
      }

      # If in a previous iteration of this loop we found a file named according
      # to the standard naming convention, compare that filename with the 
      # current one.  If the naming conventions don't match we stop sorting
      # these files by number.
      if(defined($prevMatch) && ($prevMatch ne $currMatch))
      {
         $gLogger->error("Files in this folder cannot be sorted by number " .
                         "because they do not follow a consistent naming " .
                         "convention.");
         return FALSE;
      }
      else
      {
         $prevMatch = $currMatch;
         AddFileNumEntry(\%fileNums, $fileNum, $file);
      }
   }

   # Assign a sequence number to each file by sorting the fileNums hash.
   $$seqNum_sr = 1;

   foreach $fileNum (sort {$a <=> $b} keys(%fileNums))
   {
      $files_hr->{$fileNums{$fileNum}}->{seq_num} = $$seqNum_sr;
      $$seqNum_sr++;
   }

   return TRUE;
}

#-------------------------------------------------------------------------------
# Sorts the files by their DateTimeOriginal EXIF metadata value in ascending 
# order.  The files cannot be sorted if all files do not have a valid value 
# for DateTimeOriginal.
#
# \param $_[0] [in_out] A reference to a hash of filenames keyed on the base 
#                       filename.
# \param $_[1] [in_out] A reference to a scalar that will represent the
#                       maximum sequence number once the files are sorted.
#
# \return TRUE if the files could be sorted and a sequence number is assigned 
#         to each file in the reference hash; FALSE otherwise.
#-------------------------------------------------------------------------------
sub sortFilesByTime
{
   my $files_hr  = $_[0];
   my $seqNum_sr = $_[1];

   my $exifTool = new Image::ExifTool;
   my $tag = 'DateTimeOriginal';
   my $fileDateTime = undef;

   # A temporary hash to store the filenames we process (values) keyed
   # on the DateTimeOriginal value their EXIF metadata.  This allows us to 
   # **alphanumerically** sort the keys to determine the sequence number or
   # sort order for each file.   
   my %fileDateTimes = ();

   foreach my $file (sort {lc $a cmp lc $b} keys(%$files_hr))
   {
      $exifTool->ImageInfo($files_hr->{$file}->{curr_abs_path});
      $fileDateTime = $exifTool->GetValue($tag, 'ValueConv');

      # Append a ".0" DateTimeOriginal value.  This allows us to increment
      # this final digit (see the AddFileDateTimeEntry function) in case
      # multiple files contain exactly the same value.
      #
      # Hence a DateTimeOriginal values is modified as follows:
      #
      #   2016:09:14 17:19:07 --> 2016:09:14 17:19:07.0
      #
      # It is subsequently treated and sorted as an alphanumeric value; not a
      # DateTime object.
      $fileDateTime = $fileDateTime . '.0';

      if (!defined($fileDateTime))
      {
         $gLogger->error("DateTimeOriginal EXIF data is missing for file " .
                         "'$file'.  Hence we cannot sort this folder by " .
                         "time.");
         return FALSE;
      }
      else
      {
         AddFileDateTimeEntry(\%fileDateTimes, $fileDateTime, $file);
      }
   }   

   # Assign a sequence number to each file by sorting the fileDateTimes hash.
   $$seqNum_sr = 1;

   foreach $fileDateTime (sort {lc $a cmp lc $b} keys(%fileDateTimes))
   {
      $files_hr->{$fileDateTimes{$fileDateTime}}->{seq_num} = $$seqNum_sr;
      $$seqNum_sr++;
   }

   return TRUE;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reporting Subroutines
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#-------------------------------------------------------------------------------
# Generates a report about the files that we attempted to rename.
#
# \param $_[0] [in] A reference to a hash of filenames keyed on the base 
#                   filename that need to be or have been renamed.
# \param $_[1] [in] The absolute path of the directory in which the files
#                   were processed.
#
# \return The rename report as a string.
#-------------------------------------------------------------------------------
sub generateRenameReport
{
   my $files_hr = $_[0];
   my $dirName  = $_[1];

   my $report = '';
   my $statusCounts_hr = getStatusCounts($files_hr);
  
   my $dividerLine = "=" x 77 . "\n";

   # Write header information to file.
   $report .= "\n";
   $report .= $dividerLine;
   $report .= "File Renaming Report\n";
   $report .= "\n";
   $report .= "Folder: $dirName\n";
   $report .= "\n";   
   $report .= "  Files with status 'Renamed':     $statusCounts_hr->{Renamed}\n";
   $report .= "  Files with status 'Ready':       $statusCounts_hr->{Ready}\n";
   $report .= "  Files with status 'Unprocessed': $statusCounts_hr->{Unprocessed}\n";
   $report .= "  Files with status 'Error':       $statusCounts_hr->{Error}\n";
   $report .= $dividerLine;
   $report .= "\n";

   my $numRecords  = scalar(keys(%$files_hr));
   my $dataFormat  = "%-24s | %-24s | %-23s\n";
   my $headerRow   = sprintf($dataFormat,
                             'Old Name', 'New Name', 'Status') .
                     '-' x 24 . " | " .
                     '-' x 24 . " | " .
                     '-' x 23 . "\n";

   $report .= $dividerLine;
   $report .= "$dirName ($numRecords files)\n";
   $report .= $dividerLine;

   $report .= $headerRow if ($numRecords > 0);

   foreach my $file (sort(keys(%$files_hr)))
   {
      $report .= sprintf($dataFormat,
                         $file,
                         $files_hr->{$file}->{new_name} || '',
                         $files_hr->{$file}->{status});
   }

   $report .= "$dirName ($numRecords files) - End\n\n";
   return $report;
}

#-------------------------------------------------------------------------------
# Gets a count of the number of files in each state as shown below:
#
#    {
#       'Ready' => 14,
#       'Error' => 0,
#       'Renamed' => 0
#    };
#
# \param $_[0] [in] A reference to a hash of filenames keyed on the base 
#                   filename that need to be or have been renamed.
#
# \return A reference to the status counts hash described above.
#-------------------------------------------------------------------------------
sub getStatusCounts
{
   my $files_hr = $_[0];

   my %statusCounts = (Ready       => 0,
                       Renamed     => 0,
                       Error       => 0,
                       Unprocessed => 0);

   foreach my $file (sort keys(%$files_hr))
   {
      my $status = $files_hr->{$file}->{status};

      if (exists($statusCounts{$status}))
      {
         $statusCounts{$status} = $statusCounts{$status} + 1
      }
      else
      {
         $gLogger->logdie("Unexpected file status '$status'.");
      }
   }
   
   return \%statusCounts;
}
