#!/usr/bin/perl

use strict;

use File::Basename qw(dirname);
use Getopt::Long;
use Cwd qw(abs_path);

my $specific_manifest;
my $silent = 0;

my $retval = GetOptions(
    "manifest=s" => \$specific_manifest,
    "silent" => \$silent,
    "help" => sub { Usage() },
);

my @manifests;

if ($specific_manifest)
{
    if (! -f $specific_manifest)
    {
        print "Uninstall manifest file not found.\n";
        Usage(1);
    }

    push (@manifests, $specific_manifest);
}
else
{
    @manifests = glob dirname(__FILE__) . "/.*uninstall_manifest_do_not_delete.txt";

    if (scalar(@manifests) == 0)
    {
        print "Couldn't detect any uninstall manifest files.\n";
        Usage(1);
    }
}

my @uninstallation_dirs;
my %uninstallation_links;
my %uninstallation_files;

for (@manifests)
{
    ParseManifest($_);
}

ValidateWritable();

PerformUninstall();

sub ParseManifest
{
    my $manifest = shift;
    open MANIFEST, '<', $manifest;
    while (my $line = <MANIFEST>)
    {
        chomp $line;

        next if ($line =~ m|^\s*#|);

        my @line_data = split(':', $line);
        my $data_type = $line_data[0];

        if ($data_type eq "file")
        {
            $uninstallation_files{$line_data[1]} = $line_data[2];
        }
        elsif ($data_type eq "dir")
        {
            push (@uninstallation_dirs, $line_data[1]);
        }
        elsif ($data_type eq "link")
        {
            $uninstallation_links{$line_data[1]} = $line_data[2];
        }
    }
    close MANIFEST;
}

sub ValidateWritable
{
    for my $file (keys(%uninstallation_files))
    {
        if (-f $file && ! -w $file)
        {
            Unwritable($file);
        }
    }

    for my $link (keys(%uninstallation_links))
    {
        if (-l $link && ! -w $link)
        {
            Unwritable($link);
        }
    }

    for my $dir (@uninstallation_dirs)
    {
        if (-d $dir && ! -w $dir)
        {
            Unwritable($dir);
        }
    }
}

sub Unwritable
{
    my $file = shift;

    if (!$file)
    {
        $file = "the files";
    }
    
    print <<END;
Unable to get write permissions for $file.
Ensure you have the appropriate permissions to uninstall. You may need to run
the uninstall as root or via sudo.
END
    exit(1);
}

my $MD5_Module_Detected = undef;
sub DetectMD5Module
{
    return $MD5_Module_Detected if (defined $MD5_Module_Detected);

    eval
    {
        require Digest::MD5;
        Digest::MD5->import(qw(md5_hex));
    };

    if ($@)
    {
        $MD5_Module_Detected = 0;
    }
    else
    {
        $MD5_Module_Detected = 1;
    }

    return $MD5_Module_Detected;
}

sub GetMD5
{
    my $md5;
    my $file = shift;

    if (DetectMD5Module())
    {
        open FILE, "$file";
        binmode FILE;
        my $data = <FILE>;
        close FILE;
        $md5 = md5_hex($data);
    }
    else
    {
        $md5 = `md5sum $file 2>/dev/null | awk '{print \$1}'`;
        chomp $md5;
    }

    return $md5;
}

#
# Here are the rules for an uninstall:
# 1. For each link, remove link
#    a. If link does not exist, warn user
#    b. If link is no longer a link, warn user
# 2. For each file, remove file if md5 sums match.
#    a. If md5 sums mismatch, do not remove and warn user
#    b. If file does not exist, warn user
#    c. If file is no longer a file, warn user
# 3. For each dir, remove dir in order of decreasing depth
#    a. If dir is not empty, do not remove and warn user
#    b. If dir does not exist, warn user
#    c. If dir is no longer a dir, warn user
#
sub PerformUninstall
{
    for (@manifests)
    {
        RemoveFile($_);
    }

    for my $link (keys(%uninstallation_links))
    {
        if (-l $link)
        {
            if (readlink($link) eq $uninstallation_links{$link})
            {
                RemoveFile($link);
            }
            else
            {
                print "Not removing symbolic link, it appears to have been modified after installation: $link\n" if (!$silent);
            }
        }
        elsif (-e $link)
        {
            print "Not removing expected symbolic link, it exists but is no longer a symbolic link: $link\n" if (!$silent);
        }
        else
        {
            print "Expected symbolic link, but it no longer exists: $link\n" if (!$silent);
        }
    }

    for my $file (keys(%uninstallation_files))
    {
        my $md5 = GetMD5($file);

        my $os_name = `uname -s`;

        if (! -e $file && ! -l $file)
        {
            print "Expected file, but it no longer exists: $file\n" if (!$silent);
        }
        elsif (! -f $file || -l $file)
        {
            print "Not removing expected file, it exists but is no longer a file: $file\n" if (!$silent);
        }
        elsif ($os_name !~ m/darwin/i && $md5 ne $uninstallation_files{$file})
        {
            print "Not removing file, it appears to have been modified after installation: $file\n" if (!$silent);
        }
        elsif (abs_path(__FILE__) eq $file)
        {
            #
            # We need to leave the uninstallation script if other manifests are going to use it.
            # Detect if there are any local manifests that are not currently being uninstalled.
            #
            my @local_manifests = glob dirname(__FILE__) . "/.*uninstall_manifest_do_not_delete.txt";

            my $skip_removing_script = 0;
            for my $cur_local_manifest (@local_manifests)
            {
                my $local_manifest_is_active = 0;
                for my $cur_active_manifest (@manifests)
                {
                    if ($cur_active_manifest eq $cur_local_manifest)
                    {
                        $local_manifest_is_active = 1;
                        last;
                    }
                }

                if (!$local_manifest_is_active)
                {
                    $skip_removing_script = 1;
                    last;
                }
            }

            if ($skip_removing_script)
            {
                print "Not removing uninstall script, it appears to be used with other packages: $file\n";
            }
            else
            {
                RemoveFile($file);
            }
        }
        else
        {
            RemoveFile($file);
        }
    }

    for my $dir (sort {$b cmp $a} uniq(@uninstallation_dirs))
    {
        opendir DIR, "$dir";
        my $empty = 1;
        while (my $file = readdir(DIR))
        {
            if ($file ne "." && $file ne "..")
            {
                $empty = 0;
                last;
            }
        }

        if ($empty)
        {
            RemoveDir($dir);
        }
        else
        {
            print "Not removing directory, it is not empty: $dir\n" if (!$silent);
        }
    }
}

sub uniq
{
    my %seen = ();
    my @ret = ();

    foreach my $element (@_)
    {
        unless ($seen{$element})
        {
            push @ret, $element;
            $seen{$element} = 1;
        }
    }

    return @ret;
}

sub RemoveDir
{
    my $dir = shift;

    if (!$dir)
    {
        return;
    }

    print "Removing directory $dir\n" if (!$silent);
    rmdir $dir;
}

sub RemoveFile
{
    my $file = shift;

    if (!$file)
    {
        return;
    }

    print "Removing $file\n" if (!$silent);
    unlink $file;
}

sub Usage
{
    my $code = 0;
    $code = shift;

    print <<END;

Usage:
    perl uninstall.pl <Options>
Options:
    --manifest=<PATH>   : optional path to uninstallation manifest. Defaults to .uninstall_manifest_do_not_delete.txt
    --silent            : don't print standard uninstallation messages (only print error messages)
END

    exit($code);
}
