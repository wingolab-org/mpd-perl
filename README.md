# MPD - Multiplex Primer Design

This package assists in the automation of multiplex primer design. To get the most out of this package you will need the companion C code, which you can find [here (mpd-c)](http://github.com/wingolab-org/mpd-c).

## Installation

- Compiling the c binaries. Follow the instructions here: [mpd-c](http://github.com/wingolab-org/mpd-c).
- Clone the perl MPD package (e.g., `git clone https://github.com/wingolab-org/mpd-perl.git`).
- There is a pre-build tarball of the MPD package suitable for installation with `cpanm` (i.e., [App::cpanminus](https://metacpan.org/release/App-cpanminus)). To install, `cpanm MPD.tar.gz`.
  - The tarball was created with `Dist::Zilla`. Otherwise, `Dist::Zilla` is not needed.
  - Run tests within the directory like so: `prove -l` or `prove -lv t/some_test.t`
  - Coding style and tidying is kept in `.perltidyrc` (`Perl::Tidy`) and `tidyall -a` (`Code::Tidy`) is used to tidy code before committing.
  - If you want to install `Dist::Zilla`, please see [dagolden's distribution](https://github.com/dagolden/Dist-Zilla-PluginBundle-DAGOLDEN) and [Dist::Zilla on metacpan](https://metacpan.org/pod/Dist::Zilla).
- See examples scripts in the `ex` directory or look at the tests, specifically, `t/05-Mpd.t` to see how to build and use the MPD object.

## Optional features
- The MPD package can be made to use the standalone binary for isPcr by Jim Kent. If you are not familiar with isPcr [here is a web version](https://genome.ucsc.edu/cgi-bin/hgPcr) and that has details about obtaining the source code to build the stand alone binary.
- If you use the isPcr you will need the 2bit genome of the organism.

## Usage

- Setup a configuration file in the [`YAML` format](http://www.yaml.org/).

From the `ex` (example) directory:

    ---
    BedFile: ex/markers.txt.bed      # TARGET LIST
    isPcrBinary: isPcr               # isPcr binary, optional
    TwoBitFile: hg38.2bit            # TwoBitFile, optional (needed for isPcr)
    MpdBinary: ../mpd-c/build/mpd    # mpd binary (see http://github.com/wingolab-org/mpd-c)
    MpdIdx: hg38.d14.sdx             # HASHED GENOME, see mpd-c setup
    dbSnpIdx: ds_flat.sdx            # LIST of FLAT DBSNP FILES, see mpd-c setup

    CoverageThreshold: 0.8           # The definition of "covered"
    PrimerSizeMin: 17                # Minimum primer size
    PrimerSizeMax: 27                # Maximum primer size
    PadSize: 60                      # The region around the target to search for primers

    PoolMax: 10                      # Maximum number of primers in a pool
    PoolMin: 5                       # Minimum number of primers in a pool

    Iter: 2                          # Number of iterations to try to find primers
    IncrTm: 1                        # degrees Celsius to widen the Min/Max Tm on successive trial
    IncrTmStep: 1                    # degrees Celsius to widen the Tm step (within mpd-c) on successive trial
    IncrAmpSize: 10                  # number of base pairs to widen the acceptable amplicon max/min on successive trial

    InitAmpSizeMin: 160              # Initial Minimum Amplicon Size
    InitAmpSizeMax: 240              # Initial Maximum Amplicon Size
    InitGcMin: 0.3                   # Initial Minimum %GC
    InitGcMax: 0.7                   # Initial Maximum %GC
    InitTmMin: 57                    # Initial Minimum Tm
    InitTmMax: 62                    # Initial Maximum Tm

- Create an MPD object, and call the `RunAll()` method.

From `design.pl`:

    my $m = MPD->new_with_config(
      {
        configfile  => $config_file,
        BedFile     => 'target_regions.bed',
        OutExt      => 'myGreatPrimerPools',
        OutDir      => '/temp/',
        InitTmMin   => 58,
        InitTmMax   => 61,
        MinPool     => 5,
        Debug       => 0,
        IterMax     => 2,
        RunIsPcr    => undef, # set to something perl evaluates to true if you want isPcr to check the in-silico PCR
        Act         => 1,     # set to something perl evaluates to true if you want the program to execute the mpd-c binary
        ProjectName => $out_ext,
        FwdAdapter  => '',    # your fwd adapter
        RevAdapter  => '',    # your rev adapter
        Offset      => 0,     # when printing pools where do we start?
        Randomize   => 1,     # should we shuffle the pools so they are in random order?
      }
    );
    $m->RunAll();             # run the design.

- Feel free to email the authors with questions or suggestions.
