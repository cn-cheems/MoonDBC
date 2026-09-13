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
      @argparse.Command(
        "decode",
        about="Decode a SocketCAN or candump trace as CSV.",
        positionals=[
          @argparse.PositionArg(
            "dbc",
            about="Path to the DBC file.",
            num_args=@argparse.ValueRange::single(),
          ),
          @argparse.PositionArg(
            "trace",
            about="Path to the CAN trace file.",
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
  let output = if name == "decode" {
    guard subcommand.values is { "trace": [trace_path], .. } else { return }
    let trace_source : String? = Some(@fs.read_file(trace_path).text()) catch {
      _ => None
    }
    guard trace_source is Some(trace_source) else {
      @stdio.stderr.write("moondbc: unable to read \{trace_path}\n")
      process_exit(2)
      return
    }
    @lib.run_decode_cli(path, source, trace_path, trace_source)
  } else {
    let mode = if name == "check" { @lib.CliCheck } else { @lib.CliList }
    @lib.run_cli(mode, path, source)
  }
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
