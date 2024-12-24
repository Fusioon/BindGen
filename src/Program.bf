using System;
using System.IO;
using System.Threading;
using System.Diagnostics;
using System.Collections;

namespace BindGen;

public enum EDeclKind
{
	case TypedefType,
		 ElaboratedType,
		 BuiltinType,
		 Function,
		 TextComment,
		 ParagraphComment,
		 BlockCommandComment,
		 FullComment,
		 TypedefDecl,
		 FunctionDecl,
		 ParmVarDecl,
		 DeclRefExpr,
		 FieldDecl,
		 RecordDecl,
		 VarDecl,
		 ParamCommandComment,
		 InlineCommandComment,
		 EnumConstantDecl,
		 EnumDecl,
		 PointerType,
		 StaticAssertDecl;

		public static Result<Self> FromString(StringView input)
		{
			return Enum.Parse<Self>(input);
		}
}

public enum EDeclAttr
{
	case MaxFieldAlignmentAttr,
		 TypeVisibilityAttr,
		 AlignedAttr,

		 BuiltinAttr,
		 MSAllocatorAttr,
		 DeprecatedAttr,
		 NoThrowAttr,
		 AllocSizeAttr,
		 ConstAttr,
		 ReturnsTwiceAttr,
		 AnalyzerNoReturnAttr,
		 FormatAttr,
		 DLLImportAttr,
		 NonNullAttr,
		 WarnUnusedResultAttr,
		 RestrictAttr;

	public static Result<Self> FromString(StringView input)
	{
		return Enum.Parse<Self>(input);
	}
}

class Program
{
	public delegate void GeneratorSetupDelegate(Generator gen);

	class GenerateSettings
	{
		append String _namespace;
		public StringView Namespace
		{
			get => _namespace;
			set => _namespace.Set(value);
		}

		append String _outFilePath;
		public StringView OutFilePath
		{
			get => _outFilePath;
			set => _outFilePath.Set(value);
		}

		public Stream outStream;

		public append List<StringView> includeDirs;
		public append List<StringView> targetFiles;
		public append List<StringView> includeList;
	}


	static bool VSWhere(String outpath)
	{
		ProcessStartInfo si = scope .();
		si.UseShellExecute = false;
		si.CreateNoWindow = true;
		si.SetFileNameAndArguments("vswhere");
		si.RedirectStandardOutput = true;

		FileStream ofs = scope .();
		SpawnedProcess process = scope .();
		TrySilent!(process.Start(si));
		TrySilent!(process.AttachStandardOutput(ofs));

		String buffer = scope .();
		StreamReader reader = scope .(ofs);
		while (reader.ReadLine(buffer..Clear()) case .Ok)
		{
			const String INSTALL_PATH = "installationPath: ";
			if (buffer.Contains(INSTALL_PATH))
			{
				outpath.Append(buffer.Substring(INSTALL_PATH.Length));
				return true;
			}
		}

		return false;
	}

	static Result<int> RunCommand(StringView exe, StringView workDir, StringView args, String outputBuffer)
	{
		ProcessStartInfo si = scope .();
		si.UseShellExecute = false;
		si.SetFileName(exe);
		si.SetArguments(args);
		si.SetWorkingDirectory(workDir);
		si.RedirectStandardOutput = true;

		SpawnedProcess process = scope .();
		process.Start(si);

		FileStream ofs = scope .();
		process.AttachStandardOutput(ofs);

		StreamReader reader = scope .(ofs);
		Try!(reader.ReadToEnd(outputBuffer));

		return process.ExitCode;
	}

	static bool IsValidLocation(JSONReader.JObject obj, Span<StringView> compare, bool ignoreCase, bool checkFrom)
	{
		if (let loc = obj["loc"].GetValueOrDefault().AsObject.GetValueOrDefault())
		{
			let file = loc["file"].GetValueOrDefault().AsString.GetValueOrDefault();

			if (file != null)
			{
				for (let cmp in compare)
				{
					if (file.Contains(cmp, ignoreCase))
						return true;
				}
			}

			if (checkFrom)
			{
				if (let from = loc["includedFrom"].GetValueOrDefault().AsObject.GetValueOrDefault())
				{
					let fromFile = from["file"].GetValueOrDefault().AsString.GetValueOrDefault();
					if (fromFile != null && file == null)
					{
						for (let cmp in compare)
						{
							if (fromFile.Contains(cmp, ignoreCase))
								return true;
						}
					}
				}
				else if (file == null)
					return true;
			}
		}

		return false;
	}	

	static void HandleTopLevelInnerObject(Parser parser, Span<StringView> includeFileList, JSONReader.JObject obj)
	{
		let name = obj["name"].GetValueOrDefault().AsString.GetValueOrDefault();
		let kindString = obj["kind"].GetValueOrDefault().AsString.GetValueOrDefault();

		EDeclKind kind;
		switch (EDeclKind.FromString(kindString))
		{
		case .Err:
			{
				Console.WriteLine($"Unknown kind: '{kindString}'");
				return;
			}
		case .Ok(out kind):
		}

		if (name == "sodium_init")
			NOP!();

		if (!IsValidLocation(obj, includeFileList, true, true))
		{
			return;
		}

		let inner = obj["inner"].GetValueOrDefault().AsArray.GetValueOrDefault();

		if (inner == null)
		{
			return;
		}

		switch (kind)
		{
		case .EnumDecl:
			{
			 	parser.HandleEnumDef(name, obj, inner);
			}
		case .TypedefDecl:
			{
				parser.HandleTypedef(name, obj, inner);
			}
		case .FunctionDecl:
			{
				parser.HandleFunction(name, obj, inner);
			}
		case .RecordDecl:
			{
				if (String.IsNullOrEmpty(name))
				{
					Console.WriteLine($"");
					// @TODO
					return;
				}

				parser.HandleRecord(name, obj, inner);
			}
		case .VarDecl:
			{
				parser.HandleVariable(name, obj, inner);
			}

		default:
			Console.WriteLine($"Unhandled toplevel kind: {_} ({name})");
		}
	}

	public static int Main(String[] args)
	{
		GenerateSettings settings = scope .();

		const bool SDL3 = false;
		const bool SODIUM = true;

		if (SDL3)
		{
			settings.includeDirs.Add("include/SDL_Include");
			settings.targetFiles.Add("include/SDL_include/SDL3/SDL_image.h");
			settings.includeList.Add("SDL3/");

			settings.OutFilePath = "Generated/src/SDL3_Generated.bf";
			settings.Namespace = "SDL3";
			Generate(settings, scope (gen) => {

				gen.onPrimitiveTypeResolve = new (type, alias) =>  !type.raw.Contains("SDL_", true);
				gen.definesFilter = new (def) => def.name.Contains("SDL_");
			});
		}

		if (SODIUM)
		{
			settings.includeDirs.Add("include/SODIUM_include");
			settings.targetFiles.Add("include/SODIUM_include/sodium.h");
			settings.includeList.Add("sodium");

			settings.OutFilePath = "Generated/src/Sodium_Generated.bf";
			settings.Namespace = "Sodium";
			Generate(settings, scope (gen) => {
				gen.definesFilter = new (def) =>
				{
					if (def.name.StartsWith('_'))
						return false;

					return def.name.Contains("sodium", true) || def.name.Contains("crypto");
				};
			});
		}

		return 0;
	}

	public static void Generate(GenerateSettings settings, GeneratorSetupDelegate genSetup = null)
	{
		static StringView SkipVSHeader(StringView data)
		{
			Runtime.Assert(data.StartsWith("****"));

			var data;
			for (int i < 4)
			{
				data = data.Substring(data.IndexOf('\n') + 1);
			}
			return data;
		}

		String vspath = scope .();
		if (!VSWhere(vspath))
		{
			vspath.Set(@"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\");
		}
		else
		{
			Path.Combine(vspath, @"Common7\Tools\");
		}
		Runtime.Assert(vspath.Length > 0);

		Path.Combine(vspath, "VsDevCmd.bat");

		String DUMP_AST_COMMAND;
		String PRINT_DEFINES_COMMAND;
		{
			String includeDirsString = scope .();
			for (let dir in settings.includeDirs)
				includeDirsString.AppendF($"--include-directory={dir} ");

			String targetFilesString = scope .();
			for (let f in settings.targetFiles)
				targetFilesString.AppendF($"{f} ");

			DUMP_AST_COMMAND = scope:: $"clang -Xclang -ast-dump=json {includeDirsString} -fsyntax-only {targetFilesString}";
			PRINT_DEFINES_COMMAND = scope:: $"clang -Xclang -dM -E {includeDirsString} {targetFilesString}";
		}

		let workDir = Directory.GetCurrentDirectory(.. scope .());
		String buffer = scope .();
		RunCommand("cmd.exe", workDir, scope $"/C \"{vspath}\" && {DUMP_AST_COMMAND}", buffer);

		StringView jsonText = SkipVSHeader(buffer);

		JSONReader.JSONParser jsonParser = scope .();
		let result = jsonParser.Parse(jsonText).Value.AsObject.Value;
		Parser dumpParser = scope .();
		let innerArray = result["inner"].Value.AsArray.Value;

		Span<StringView> includesList = settings.includeList;
		if (includesList.IsEmpty)
			includesList = settings.targetFiles;

		for (let val in innerArray)
		{
			HandleTopLevelInnerObject(dumpParser, includesList, val.AsObject);
		}

		buffer.Clear();
		RunCommand("cmd.exe", workDir, scope $"/C \"{vspath}\" && {PRINT_DEFINES_COMMAND}", buffer);
		PreprocParser preprocParser = scope .();

		StringView definesText = SkipVSHeader(buffer);
		for (let line in definesText.Split('\n', .RemoveEmptyEntries))
		{
			preprocParser.HandleDefine(line);
		}

		Generator gen = scope .();

		if (genSetup != null)
			genSetup(gen);

		Stream stream = settings.outStream;
		if (stream == null)
		{
			FileStream fs = scope:: .();
			fs.Open(settings.OutFilePath, .Create, .Write);
			stream = fs;
		}

		gen.Generate(preprocParser, dumpParser, settings.Namespace, stream);
	}
}