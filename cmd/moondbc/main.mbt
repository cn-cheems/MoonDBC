///|
extern "c" fn process_exit(code : Int) = "exit"

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "moondbc",
    version="0.1.0",
    about="Inspect and validate CAN DBC databases.",
    subcommands=[
      @argparse.Command("check", about="Parse and validate a DBC file.", positionals=[
        @argparse.PositionArg(
          "dbc",
          about="Path to the DBC file.",
          num_args=@argparse.ValueRange::single(),
        ),
      ]),
      @argparse.Command(
        "list",
        about="List messages and signals in a DBC file.",
        positionals=[
          @argparse.PositionArg(
            "dbc",
            about="Path to the DBC file.",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
      ),
    ],
    subcommand_required=true,
  )
}

///|
async fn main {
  let matches = command().parse(argv=@env.args()[1:])
  guard matches.subcommand is Some((name, subcommand)) else { return }
  guard subcommand.values is { "dbc": [path], .. } else { return }
  let source : String? = Some(@fs.read_file(path).text()) catch { _ => None }
  guard source is Some(source) else {
    @stdio.stderr.write("moondbc: unable to read \{path}\n")
    process_exit(2)
    return
  }
  let mode = if name == "check" { @lib.CliCheck } else { @lib.CliList }
  let output = @lib.run_cli(mode, path, source)
  if !output.stdout.is_empty() {
    @stdio.stdout.write(output.stdout)
  }
  if !output.stderr.is_empty() {
    @stdio.stderr.write(output.stderr)
  }
  if output.exit_code != 0 {
    process_exit(output.exit_code)
  }
}
