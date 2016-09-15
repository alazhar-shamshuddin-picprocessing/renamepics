#############################################################################

=head1 NAME

renamepics - provides services to rename and renumber picure and movie
             files in a given directory.

=head1 SYNOPSIS

renamepics -[rtnf] dir

=head1 OPTIONS

=over 8

=item B<-f>

Forces the program to rename files even if the specified directory
contains files with a non-standard naming convention (those files are
ignored).

=item B<-n>

Fixes the Numbering scheme to ensure all files are numbered sequentially,
starting from 1.  Existing files are renamed, if necessary, to ensure
intermediate numbers are not skipped.  All files in the specified
directory must follow a recognized numbering/naming convention.

=item B<-r>

Recursively processes sub-directories.

=item B<-t>

This option does NOT work. Files ARE renamed.  The intent is for it to be
a test command.  A list of files that would be renamed are output, but
no files would be renamed. 

=item B<-?, -h>

Displays a brief Help message.

=item B<-m>

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

© Copyright Alazhar Shamshuddin, 2008, All Rights Reserved.

=cut

#############################################################################

use strict;
use warnings;

use Data::Dumper;     # For debugging data structures.
use File::Copy;       # For renaming (copying) files.
use File::Spec;       # For managing file paths.
use Getopt::Long;     # For command-line options processing.
use Log::Log4perl;    # For logging.
use Pod::Usage;       # For printing usage clause and man page.


#############################################################################
# Global Variables
#############################################################################
my $gMaxDigits           = 4;
my $gRenameReporFilename = 'rename_report.txt';

my $gLogger              = undef;
my %gCmds                = ();
my %gRenameReport        = ();


#############################################################################
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
#            - getFilesToBeRenamed
#            - isRenumberingRequired
#            - processDir
#            - renameFiles
#            - renameFiles_helper
#            - renameFiles_preProcess
#            - renumberFile
#        - Reporting
#            - containsAll
#            - containsAtLeastOne
#            - genRenameReportStatusSummary
#            - printDirectoryList
#            - printDirectoryReport
#            - writeRenameReportToFile
#############################################################################

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main();
sub main
{
   initLogger(0, \$gLogger);
   $gLogger->info("*** Executing $0. ***");

   processCmdLineArgs(\%gCmds);

   foreach my $dir (@{$gCmds{directories}})
   {
      $dir= File::Spec->canonpath($dir);
      processDir($dir);
   }

   writeRenameReportToFile($gRenameReporFilename, \%gRenameReport);

   # Log a message to show successful completion.
   $gLogger->info("*** $0 executed successfully. ***");
   print "\n*** $0 executed successfully. ***\n";
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Intialization Subroutines
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#----------------------------------------------------------------------------
# Initializes the logging functionality.
#
# \param $_[0] [in]  The logging configurating filename.
# \param $_[1] [out] A reference to a logger.
#
# \return None.
#----------------------------------------------------------------------------
sub initLogger
{
   # Initialize the logger.
   my $logConfigFile = $_[0];
   my $logger_sr     = $_[1];

   if ( -r $logConfigFile )
   {
      Log::Log4perl->init($logConfigFile);
   }
   else
   {
      # Configuration in a string.
      my $logConfigString = q(
         log4perl.rootLogger=TRACE, FILE, SCREEN

         #--------------------------------------------------------------------
         # For writing log messages to a file in the following format:
         #
         #   (%d)                (%r)  (%p)  (%l)                     (%m%n)
         #   2008/03/26 15:16:14 [127] ERROR main::fnc file.pl (599): Message.
         #--------------------------------------------------------------------
         log4perl.appender.FILE          = Log::Log4perl::Appender::File
         log4perl.appender.FILE.filename = renamepics.log
         log4perl.appender.FILE.mode     = clobber
         log4perl.appender.FILE.layout   = PatternLayout
        #log4perl.appender.FILE.layout.ConversionPattern = %d [%r] %p %l: %m%n
         log4perl.appender.FILE.layout.ConversionPattern = %p: %m%n

         #--------------------------------------------------------------------
         # For writing log messages to the screen in the following format:
         #
         #   (%r)  (%p)  (%l)                     (%m%n)
         #   [127] ERROR main::fnc file.pl (599): Message.
         #--------------------------------------------------------------------
         log4perl.appender.SCREEN        = Log::Log4perl::Appender::Screen
         log4perl.appender.SCREEN.stderr = 0
         log4perl.appender.SCREEN.layout = PatternLayout
         log4perl.appender.SCREEN.layout.ConversionPattern = [%r] %p %l: %m%n
         );

      Log::Log4perl::init( \$logConfigString );
   }

   $$logger_sr = Log::Log4perl->get_logger("$0");
   die "FATAL: Could not initialize the logger." unless $$logger_sr;
}


#----------------------------------------------------------------------------
# Processes command line arguments, and informs the user of invalid
# parameters.  All command-line options/values are returned in a
# multi-dimensional hash for ease of access.
#
# This subroutine also displays the usage clause if there are any errors,
# or the help or manual pages if the user explicitely requests them.
# Displaying the usage clause, help page and manual pages via pod2usage
# automatically terminates this script.
#
# \param $_[0] [out] A referefence to a hash.
# 
# \return None.
#----------------------------------------------------------------------------
sub processCmdLineArgs
{
   Pod::Usage::pod2usage(1) unless
      Getopt::Long::GetOptions(
        "test|t"      => \$gCmds{test},
        "force|f"     => \$gCmds{force},
        "recursive|r" => \$gCmds{recursive},
        "renumber|n"  => \$gCmds{renumber},
        "help|?"      => \$gCmds{help},
        "man"         => \$gCmds{man}
      );

   Pod::Usage::pod2usage(1) if $gCmds{help};
   Pod::Usage::pod2usage( -verbose => 2 ) if $gCmds{man};

   $gCmds{directories} = [@ARGV];
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Renaming Subroutines
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#----------------------------------------------------------------------------
# Generates a new filename based on the files original name and the
# specified file number.
#
# Note that this subroutine does not rename the file.
#
# \param $_[0] [in] The file number.
# \param $_[1] [in] The original file name.
#
# \return The new filename.
#----------------------------------------------------------------------------
sub generateNewName
{
   my $picNum  = $_[0];
   my $oldName = $_[1];

   my $numDigits = length( $picNum );

   for( my $i = $gMaxDigits - $numDigits; $i > 0; --$i )
   {
      $picNum = "0" . $picNum;
   }

   my ($volume, $directories, $file) = File::Spec->splitpath($oldName);

   $file =~ m/^([a-z0-9_]+?)[_-]?\d{0,4}(\.[a-z]{3}$)/i;
   $file = "$1_$picNum" . lc($2);

   return File::Spec->catfile($directories, $file);
}


#----------------------------------------------------------------------------
# Gets the files that are to be renamed.
#
# Only files with following extension are 'renamable', and therefore
# returned by this subroutine.
#
#    1. JPG
#    2. WMV
#
# Parameter 0 must be a reference to a hash of arrays keyed on the file
# extension (in uppercase, without the period).  The arrays should contain
# the file names.
#
# \param $_[0] [in] A reference to a hash of files organized by their
#                   extension.
#
# \return A reference to an array of files.
#----------------------------------------------------------------------------
sub getFilesToBeRenamed
{
   my $filesByType_hr = $_[0];

   my @filesToBeRenamed = ();

   foreach my $key (sort keys %$filesByType_hr)
   {
      if ($key eq 'JPG' || $key eq 'WMV')
      {
         push(@filesToBeRenamed, @{$filesByType_hr->{$key}});
      }
   }

   return \@filesToBeRenamed;
}


#----------------------------------------------------------------------------
# Determines whether or not the files need to be renumbered.
#
# A set of files are thought to require renumbering if the provided hash
# (Parameter 1) is different from the hash produced by the renumberFiles
# subroutine.
#
# \param $_[0] [in] A reference to a hash of filenames keyed on integer
#                   values.
# \param $_[1] [in] The starting number used to rename the files.  If it
#                   is omitted, 1 is used as the default.
#
# \return True is renumbering is required; false otherwise.
#----------------------------------------------------------------------------
sub isRenumberingRequired
{
   my $files_hr = $_[0];
   my $startNum = $_[1];

   # Assume a default starting number of 1, if startNum is undefined.
   if(!defined $startNum)
   {
      $startNum = 1;
   }

   # Assume renumbering is not required; set to false.
   my $isRenumberingRequired = 0;

   # Sort the hash keys numerically.
   my @picNums = sort {$a <=> $b} keys %$files_hr;

   foreach my $picNum (@picNums)
   {
      if($picNum != $startNum)
      {
         # Renumbering is required; set to true;
         $isRenumberingRequired = 1;
         last;
      }

      ++$startNum;
   }

   return $isRenumberingRequired;
}


#----------------------------------------------------------------------------
# Process the specified directory of files.  If the -r command line option
# is specified, subfolders rooted at the specified directory are also
# processed.
#
# \param $_[0] [in] The directory to be processed.
#
# \return None.
#----------------------------------------------------------------------------
sub processDir
{
   my $dir = $_[0];

   opendir(my $dir_fh, $dir) or
      $gLogger->logdie("Cannot opendir '$dir': $!");

   $gLogger->info("Processing '$dir'.");

   my @subDirs      = ();
   my %filesByType  = ();
   my %renameReport = ();

   foreach my $item ( sort readdir($dir_fh) )
   {
      # Skip the current and parent directory markers.
      if( $item eq '.' || $item eq '..' )
      {
         next;
      }

      # Rename $item to include relative path information.
      my $itemWithPath = File::Spec->catfile($dir, $item);
      $itemWithPath = File::Spec->canonpath($itemWithPath);

      # If we have to recursively process subdirectories, save them in
      # a special list that we will process after we completely finish
      # processing this directory ($dir).
      if( $gCmds{recursive} && -d $itemWithPath )
      {
         push(@subDirs, $itemWithPath)
      }

      if( -f $itemWithPath )
      {
         if( $item =~ m!.*\.(.*)!i )
         {
            my $type = uc($1);
            push @{$filesByType{$type}}, $itemWithPath;
         }
         else
         {
            push @{$filesByType{NO_TYPE}}, $itemWithPath;
         }
      }
   }
   closedir($dir_fh);

   renameFiles(getFilesToBeRenamed(\%filesByType), \%renameReport);
   $gRenameReport{$dir} = \%renameReport;

   # Recursively process subdirectories if the -r flag was specified on
   # the command line.
   if( $gCmds{recursive} )
   {
      foreach my $item (@subDirs)
      {
         processDir($item);
      }
   }
}


#----------------------------------------------------------------------------
# Renames the files in the specified array if they follow a consistent
# naming/numbering convention or if the -f command-line option is
# specified.
#
# This method (and its helpers) populate the rename record hash with
# information on how each file is renamed.
#
# \param $_[0] [in]     A reference to a list (array) of files.
# \param $_[1] [in-out] A reference to rename record hash for the
#                       directory being processed.
#
# \return None.
#----------------------------------------------------------------------------
sub renameFiles
{
   my $files_ar        = $_[0];
   my $renameRecord_hr = $_[1];

   # Current and previous matches store the base filenames, excluding
   # the file extension and period. They are used to verify whether
   # all the specified files follow the same naming/numbering convention.
   my $prevMatch = undef;
   my $currMatch = undef;

   # Files that are not renamed get stored in the rejected array; those
   # that are renamed are stored in the renamed hash keyed on the filename.
   my @reject = ();
   my %rename = ();

   foreach my $fileWithPath (@{$files_ar})
   {
      # Get the base filename.
      my ($volume, $path, $file) = File::Spec->splitpath($fileWithPath);

      # Create a record for this file for reporting purposes.
      $renameRecord_hr->{$fileWithPath} = {old_name => $file,
                                           new_name => '',
                                           status   => 'New'
                                          };

      if($file =~ m/^([a-z0-9_]+?)([_-]?)(\d{0,4})\.[a-z]{3}$/i)
      {
         # The current match includes only the base filename, minus
         # the extension.
         $currMatch = File::Spec->catfile($path, lc($1));
         my $picNum = undef;

         if($3)
         {
            $picNum = $3;
         }
         else
         {
            $picNum = 0;
         }

         if($prevMatch)
         {
            # If in a previous iteration of this loop we found a file
            # named according to the standard naming convention, compare
            # that filename with the current one.  If the naming
            # naming conventions don't match, we assume the first
            # convention is valid, and 'reject' all files that don't
            # adhere to it.
            #
            # Rejected files are never renamed.  In the presence of
            # rejected files, however, non-rejects may be renamed if the
            # -f command-line option was specified.
            if($prevMatch ne $currMatch)
            {
               $renameRecord_hr->{$fileWithPath}->{status} = 'Rejected';
               push(@reject, $file);
            }
            else
            {
               $rename{$picNum} = $fileWithPath;
            }
         }
         else
         {
            $prevMatch = $currMatch;
            $rename{$picNum} = $fileWithPath;
         }
      }
      else
      {
         # The filename does not follow a recognized naming/numbering
         # convention and is, therefore, rejected.
         $renameRecord_hr->{$fileWithPath}->{status} = 'Rejected';
         push(@reject, $file);
      }
   }

   # Rename the files only if there are no rejects (files with
   # inconsistent naming/numbering conventions) or if the -f command
   # line option was specified.
   if(!@reject || $gCmds{force})
   {
      renameFiles_helper(\%rename, $renameRecord_hr);
   }
}


#----------------------------------------------------------------------------
# Renames each file in the specified hash.  New filenames are generated
# via the generateNewName subroutine.
#
# If the -n command-line option is specified, the file hash is rekeyed
# on numbers that flow sequentially.
#
# This method (and its helpers) populate the rename record hash with
# information on how each file is renamed.
#
# \param $_[0] [in-out] A reference to a hash of filenames keyed on
#                       integer values (typically picture numbers).
# \param $_[1] [in-out] A reference to rename record hash containing
#                       those files that are to be renamed.
#
# \return None.
#----------------------------------------------------------------------------
sub renameFiles_helper
{
   my $files_hr        = $_[0];
   my $renameRecord_hr = $_[1];

   if($gCmds{renumber})
   {
      $files_hr = renumberFiles($files_hr);
   }

   # We rename the files in a two step process.  The pre-process step
   # does everything except for rename the files.  We do this to detect
   # possible errors.  If errors exist, we do not process this directory
   # further.  Doing so risks overwriting files in naming collisions,
   # thereby lossing or corrupting existing data.  If no errors are
   # found, however, we repeat much of this process "for real".
   #
   # TODO: Find a more efficient way of doing this check.
   my $errorsExist = renameFiles_preProcess($files_hr, $renameRecord_hr);

   if(!$errorsExist)
   {
      foreach my $picNum (sort keys %$files_hr)
      {
         # Verify that we are, in fact, supposed to process this file.
         # If its status is not 'New', abort.
         if($renameRecord_hr->{$files_hr->{$picNum}}->{status} ne 'New')
         {
            $gLogger->logdie(
               "Invalid status. Cannot rename file '$files_hr->{$picNum}' ",
               "because its status is set to ",
               "'$renameRecord_hr->{$files_hr->{$picNum}}->{status}' not ",
               "'New'.");
         }

         my $newName = generateNewName($picNum, $files_hr->{$picNum});

         if((-e $newName) &&
            (lc($newName) ne lc($files_hr->{$picNum})))
         {
            # This if statement checks whether the new filename exists
            # and if it is different for the current filename -- ignoring
            # case because the Windows file system is case insensitive.
            #
            # It is NOT an error if the two filenames are the same with
            # the exception of case (e.g., Something_0001.JPG and
            # Something_0001.jpg).  In other words, we will not abort in
            # this case.  We will only abort if there is a real
            # naming collision and we risk overwriting another file.
            #
            # Note that the preprocess step (renameFiles_preProcess)
            # should detect this error and we should never enter this
            # block of code.
            $gLogger->logdie("Cannot rename '$files_hr->{$picNum}' to ",
                             "an existing file '$newName'.");
         }
         else
         {
            # Rename the file.
            move($files_hr->{$picNum}, $newName) or
               $gLogger->error("Could not rename file '$files_hr->{$picNum}': $!");
            $gLogger->info("Renamed $files_hr->{$picNum} to $newName.");

            # Update the files status for reporting puposes.
            $renameRecord_hr->{$files_hr->{$picNum}}->{status} = 'Renamed';
         }
      }
   }
}


#----------------------------------------------------------------------------
# Conducts a test run of the file renaming process, and populates the
# new filename in the rename record hash (Parameter 1).
#
# Files are renamed in a two step process.  This pre-process step does
# everything except for rename the files.  This is done to detect
# possible errors.  The caller is responsible for checking the return
# value and taking the appropriate measures in the event of an error.
#
# TODO: Find a more efficient way of doing this check.
#
# \param $_[0] [in]     A reference to a hash of filenames keyed on
#                       integer values (typically picture numbers).
# \param $_[1] [in-out] A reference to rename record hash containing
#                       those files that are to be renamed.
#
# \return True if there is an error; false otherwise.
#----------------------------------------------------------------------------
sub renameFiles_preProcess
{
   my $files_hr        = $_[0];
   my $renameRecord_hr = $_[1];

   my $errorsExist = 0;

   foreach my $picNum (sort keys %$files_hr)
   {
      # Verify that we are, in fact, supposed to process this file.
      # If its status is not 'New', log an error and set the return
      # value to true.
      if($renameRecord_hr->{$files_hr->{$picNum}}->{status} ne 'New')
      {
         $errorsExist = 1;
         $gLogger->error(
            "Invalid status. Cannot rename '$files_hr->{$picNum}' ",
            "because its status is set to ",
            "'$renameRecord_hr->{$files_hr->{$picNum}}->{status}', ",
            "not 'New'.");
         last;
      }

      my $newName = generateNewName($picNum, $files_hr->{$picNum});
      my ($volume, $directories, $file) = File::Spec->splitpath($newName);
      $renameRecord_hr->{$files_hr->{$picNum}}->{new_name} = $file;

      if((-e $newName) &&
         (lc($newName) ne lc($files_hr->{$picNum})))
      {
         # This if statement checks whether the new filename exists
         # and if it is different for the current filename -- ignoring
         # case because the Windows file system is case insensitive.
         #
         # It is NOT an error if the two file names are the same with
         # the exception of case (e.g., Something_0001.JPG and
         # Something_0001.jpg).  It is only an error if there is a real
         # naming collision and we risk overwriting another file.
         $errorsExist = 1;
         $gLogger->error("Cannot rename '$files_hr->{$picNum}' to ",
                         "an existing file '$newName'.");

         $renameRecord_hr->{$files_hr->{$picNum}}->{status} =
            'Error - Naming conflict';
      }
   }

   return $errorsExist;
}


#----------------------------------------------------------------------------
# Renumbers the files.
#
# Assuming that the following hash is provided as input with a starting
# number (Parameter 1) of 101...
#
#    {
#       '1'   => 'Something.JPG',
#       '2'   => 'Something-1.JPG',
#       '3'   => 'Something-2.JPG',
#       '60'  => 'Something-60.JPG'
#    };
#
# A reference the the following, renumbered hash would be returned:
#
#    {
#       '101' => 'Something.JPG',
#       '102' => 'Something-1.JPG',
#       '103' => 'Something-2.JPG',
#       '104' => 'Something-60.JPG'
#    };
#
# Note that hash keys need not correspond to filenames.
#
# \param $_[0] [in] A reference to a hash of filenames keyed on integer
#                   values (typically picture numbers).
# \param $_[1] [in] The starting number used to rename the files.  If it
#                   is omitted, 1 is used as the default.
#
# \return A reference to a renumbered hash, as described above.
#----------------------------------------------------------------------------
sub renumberFiles
{
   my $files_hr = $_[0];
   my $startNum = $_[1];

   # Assume a default starting number of 1, if startNum is undefined.
   if(!defined $startNum)
   {
      $startNum = 1;
   }

   # Sort the hash keys numerically.
   my @picNums = sort {$a <=> $b} keys %$files_hr;
   my %renumberedFiles = ();

   foreach my $picNum (@picNums)
   {
      $renumberedFiles{$startNum} = $files_hr->{$picNum};
      ++$startNum;
   }

   return \%renumberedFiles;
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reporting Subroutines
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#----------------------------------------------------------------------------
# Determines whether or not all files in the specified rename report
# (Parameter 1) contains the same status (Parameter 0).
#
# \param $_[0] [in] The status of interest.
# \param $_[1] [in] A reference to the rename report sub-hash of the
#                   desired directory.
#
# \return True if all flles in the given report contain the same status;
#         false otherwise.
#----------------------------------------------------------------------------
sub containsAll
{
   my $status       = $_[0];
   my $dirReport_hr = $_[1];

   my $containsAll  = undef;

   if(keys %$dirReport_hr)
   {
      $containsAll = 1;
   }
   else
   {
      $containsAll = 0;
   }

   foreach my $file (sort keys %$dirReport_hr)
   {
      if($dirReport_hr->{$file}->{status} !~ m!$status!i)
      {
         $containsAll = 0;
         last;
      }
   }

   return $containsAll;
}


#----------------------------------------------------------------------------
# Determines if at least one file in the given rename report (Parameter 1)
# contains the specified status (Parameter 0).
#
# \param $_[0] [in] The status of interest.
# \param $_[1] [in] A reference to the rename report sub-hash of the
#                   desired directory.
#
# \return True if at least one file in the given report contains the
#         specified status; false otherwise.
#----------------------------------------------------------------------------
sub containsAtLeastOne
{
   my $status       = $_[0];
   my $dirReport_hr = $_[1];

   my $containsAtLeastOne = 0;

   foreach my $file (sort keys %$dirReport_hr)
   {
      if($dirReport_hr->{$file}->{status} =~ m!$status!i)
      {
         $containsAtLeastOne = 1;
         last;
      }
   }

   return $containsAtLeastOne;
}


#----------------------------------------------------------------------------
# Generates a rename report status summary.
#
# The status summary includes the number of directories that contain:
#    - At least one file with an 'Error' status.
#    - At least one file with a 'Rejected' status.
#    - All files with a 'Renamed' status.
#    - All files with a 'New' (or unprocessed) status.  This includes
#      directories with no files.
# 
# The status summary is returned as a reference to the following hash:
#
#    {
#       error      => [array of directory names]
#       rejected  => [array of directory names],
#       renamed   => [array of directory names],
#       no_change => [array of directory names]
#    }
#
# \param $_[0] [in] A reference to the rename report hash (for all
#                   directories).
#
# \return A reference to the summary hash described above.
#----------------------------------------------------------------------------
sub genRenameReportStatusSummary
{
   my $renameReport_hr = $_[0];

   my %summary = (error     => [],
                  rejected  => [],
                  renamed   => [],
                  no_change => []);

   foreach my $dir (sort keys %$renameReport_hr)
   {
      if(containsAtLeastOne('Error', $renameReport_hr->{$dir}))
      {
         push(@{$summary{error}}, $dir);
      }

      if(containsAtLeastOne('Rejected', $renameReport_hr->{$dir}))
      {
         push(@{$summary{rejected}}, $dir);
      }

      if(containsAll('Renamed', $renameReport_hr->{$dir}))
      {
         push(@{$summary{renamed}}, $dir);
      }

      if(containsAll('New', $renameReport_hr->{$dir}) ||
         scalar(keys %{$renameReport_hr->{$dir}}) == 0)
      {
         push(@{$summary{no_change}}, $dir);
      }
   }

   return \%summary;
}


#----------------------------------------------------------------------------
# Prints the specified list of directory names with under the given status
# in the rename report's status summary section.
#
# \param $_[0] [in] The handle of the output device or file to which the
#                   report must be printed.
# \param $_[1] [in] A reference to a list (array) of directories with 
#                   specified status.
# \param $_[2] [in] The status associated with the given list of directory
#                   names.
#
# \return None.
#----------------------------------------------------------------------------
sub printDirectoryList
{
   my $outputLoc  = $_[0];
   my $dirList_ar = $_[1];
   my $status     = $_[2];

   print $outputLoc "   $status (", scalar(@$dirList_ar), " folders)\n";

   foreach my $dir (@$dirList_ar)
   {
      print $outputLoc "      $dir\n";
   }
}


#----------------------------------------------------------------------------
# Print the rename report of the specified directory.
#
# \param $_[0] [in] The handle of the output device or file to which the
#                   report must be printed.
# \param $_[1] [in] A reference to the rename report sub-hash of the
#                   desired directory.
# \param $_[2] [in] The name of the corresponding directory.
#
# \return None.
#----------------------------------------------------------------------------
sub printDirectoryReport
{
   my $outputLoc    = $_[0];
   my $dirReport_hr = $_[1];
   my $dirName      = $_[2];

   my $numRecords  = scalar(keys %$dirReport_hr);
   my $dividerLine = "=" x 77 . "\n";
   my $dataFormat  = "%-24s | %-24s | %-23s\n";
   my $headerRow   = sprintf($dataFormat,
                             'Old Name', 'New Name', 'Status') .
                     '-' x 24 . " | " .
                     '-' x 24 . " | " .
                     '-' x 23 . "\n";

   print $outputLoc $dividerLine;
   print $outputLoc "$dirName ($numRecords files)\n";
   print $outputLoc $dividerLine;

   print $outputLoc $headerRow if($numRecords > 0);

   foreach my $file (sort keys %$dirReport_hr)
   {
      printf $outputLoc $dataFormat,
             $dirReport_hr->{$file}->{old_name},
             $dirReport_hr->{$file}->{new_name},
             $dirReport_hr->{$file}->{status};
   }

   print $outputLoc "$dirName ($numRecords files) - End\n\n\n";
}


#----------------------------------------------------------------------------
# Generates a rename report and writes it to disk.
#
# \param $_[0] [in] The name of the file to which the report must be
#                   written.  (The current working directory is assumed
#                   if the filename excludes path information.)
# \param $_[1] [in] A reference to the rename report hash (for all
#                   directories).
#
# \return None.
#----------------------------------------------------------------------------
sub writeRenameReportToFile
{
   my $outFile         = $_[0];
   my $renameReport_hr = $_[1];

   open(my $outFile_fh, ">$outFile") or
      $gLogger->logdie("Could not open file '$outFile': $!");

   my $statusSummary_hr = genRenameReportStatusSummary($renameReport_hr);   
   my $dividerLine = "=" x 77 . "\n";

   # Write header information to file.
   print $outFile_fh $dividerLine;
   print $outFile_fh "Picture Renaming Report\n";
   print $outFile_fh "Summary:\n";
   print $outFile_fh "   Number of Folders Processed: ", scalar(keys %$renameReport_hr), "\n";
   print $outFile_fh "      with at least one error:  ", scalar(@{$statusSummary_hr->{error}}), "\n";
   print $outFile_fh "      with at least one reject: ", scalar(@{$statusSummary_hr->{rejected}}), "\n";
   print $outFile_fh "      with all files renamed:   ", scalar(@{$statusSummary_hr->{renamed}}), "\n";
   print $outFile_fh "      with no changes:          ", scalar(@{$statusSummary_hr->{no_change}}), "\n";
   print $outFile_fh "\n";
   print $outFile_fh "Folders:\n";
   printDirectoryList($outFile_fh, $statusSummary_hr->{error}, 'with errors');
   printDirectoryList($outFile_fh, $statusSummary_hr->{rejected}, 'with rejected files');
   printDirectoryList($outFile_fh, $statusSummary_hr->{renamed}, 'with all files successfully renamed');
   printDirectoryList($outFile_fh, $statusSummary_hr->{no_change}, 'with no changes');
   print $outFile_fh $dividerLine;
   print $outFile_fh "\n\n";

   foreach my $dir (sort keys %$renameReport_hr)
   {
       # Write the rename report for each directory to file.
       printDirectoryReport($outFile_fh, $renameReport_hr->{$dir}, $dir);
   }
}
