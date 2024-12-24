using System;
using System.Collections;

namespace BindGen;

class Parser : ITypedAllocator
{
	public enum EStorageClassKind
	{
		case Unknown = 0,
		Extern = 1;

		public static Self FromString(StringView value)
		{
			switch (value)
			{
			case "extern":
				return .Extern;
			}

			if (value.Length > 0)
				NOP!();
			return .Unknown;
		}	
	}

	public class Comment
	{
		public enum EKind
		{
			Block,
			Line
		}
		public append String value;
		public Comment prev;
	}

	public class TypeDef
	{
		public append String name;
		public Comment comment;

		public TypeDef baseType;

	}

	public class EnumDef : TypeDef
	{
		public class NameValuePair
		{
			public append String name;
			public append String value;
			public Comment comment;
		}	

		public append List<NameValuePair> values;
	}

	public class TypeRef
	{
		public String raw;

		public append String typeString;
		//public TypeRef next;
		public bool isConst;
		public bool isRef;
		public int ptrDepth;

		public List<int32> sizedArray;

		public TypeDef typeDef;
	}

	public class VariableDecl
	{
		public append String name;
		public append TypeRef type;
	}

	public class GlobalVariableDecl : VariableDecl
	{
		public EStorageClassKind storageKind;
	}

	public class StructTypeDef : TypeDef
	{
		public enum ETag
		{
			case Unknown,
				Struct,
				Class,
				Union;

			public static Result<Self> FromString(StringView input)
			{
				switch (input)
 				{
					case "struct": return Self.Struct;
				 	case "union": return Self.Union;
					case "class": return Self.Class;
				}
				return .Err;
			}
		}


		public ETag tag;
		public append List<VariableDecl> fields;

		public List<TypeDef> innerTypes;
		public bool isCompleteDef;
	}

	public class FunctionTypeDef : TypeDef
	{
		public bool typeOnly;
		public append TypeRef functionType;

		public append TypeRef resultType;
		public append List<VariableDecl> args;
		public bool isVarArg;
		public EStorageClassKind storageKind;

		public bool isBuiltIn;
		public bool isConst;
		public bool isDeprecated;
		public bool isMSAlloc;

		public append List<EDeclAttr> attrs;
		public bool HasAttr(EDeclAttr attr) => attrs.Contains(attr);
	}

	public enum ETypeAliasFlags
	{
		None = 0x00,
		Primitive = 0x01,
		Struct = 0x02,
		Enum = 0x04,
		Function = 0x08,

		ForceGenerate = 0x40,
		Resolved = 0x80,
	}

	public class TypeAliasDef : TypeDef
	{
		public append TypeRef alias;

		public ETypeAliasFlags flags;
	}

	append BumpAllocator alloc;


	public append Dictionary<String, TypeDef> _types;

	public append List<EnumDef> _enums;
	public append List<StructTypeDef> _structs;
	public append List<FunctionTypeDef> _functions;

	public append Dictionary<String, TypeAliasDef> _aliasMap;

	public append List<GlobalVariableDecl> globalVars;

	public static bool DefaultFunctionFilter(StringView name, bool isImplicit, bool isInline, StringView storageClass)
	{
		if (isImplicit || isInline)
			return false;

		if (storageClass != "extern")
			return false;

		return true;
	}

	public void AssignComment(ref Comment targetField, Comment value)
	{
		if (value == null)
			return;

		Runtime.Assert(value.prev == null);
		value.prev = targetField;
		targetField = value;
	}

	public Comment HandleComment(JSONReader.JObject object)
	{
		return null;
	}

	JSONReader.JValue TryFindValue(JSONReader.JObject obj)
	{
		let inner = obj["inner"].GetValueOrDefault().AsArray.GetValueOrDefault();
		if (inner == null)
			return .NULL;

		for (let v in inner)
		{
			let o = v.AsObject.GetValueOrDefault();
			if (o != null)
			{
				if(o["value"] case .Ok(let val))
				{
					return val;
				}

				let v = TryFindValue(o);
				if (v != .NULL)
					return v;
			}
		}

		return .NULL;
	}

	void HandleEnumConstDef(EnumDef def, JSONReader.JObject obj)
	{
		let valueName = obj["name"].GetValueOrDefault().AsString.GetValueOrDefault();
		Runtime.Assert(valueName != null && valueName.Length > 0);

		let result = TryFindValue(obj);

		readonly EnumDef.NameValuePair kv = new:alloc .();
		kv.name.Set(valueName);

		if (result != .NULL)
		{
			Runtime.Assert(result case .STRING);
			kv.value.Set(result.AsString);
		}
		else
		{
			//Console.WriteLine($"Failed to find value for {valueName}");
		}
		def.values.Add(kv);
	}

	public EnumDef HandleEnumDef(StringView name, JSONReader.JObject object, JSONReader.JArray inner)
	{
		Runtime.Assert(name.Length > 0);

		if (_types.TryAddAlt(name, let keyPtr, let valPtr) == false)
		{
			Runtime.Assert((*valPtr) is EnumDef);
			return (EnumDef)(*valPtr);
		}	

		let def = new:alloc EnumDef();
		_enums.Add(def);

		def.name.Set(name);

		*keyPtr = def.name;
		*valPtr = def;

		for (let v in inner)
		{
			let obj = v.AsObject.GetValueOrDefault();
			if (obj == null)
				Runtime.FatalError();

			let kindString = obj["kind"].GetValueOrDefault().AsString.GetValueOrDefault();

			EDeclKind kind;
			switch (EDeclKind.FromString(kindString))
			{
			case .Err:
				{
					Console.WriteLine($"[HandleEnumDef] Unknown kind: '{kindString}'");
					continue;
				}
			case .Ok(out kind):
			}

			switch (kind)
			{
			case .FullComment, .TextComment, .ParagraphComment, .BlockCommandComment, .ParamCommandComment, .InlineCommandComment:
				AssignComment(ref def.comment, HandleComment(obj));
			case .EnumConstantDecl:
				{
					HandleEnumConstDef(def, obj);
				}

			default:
				Console.WriteLine($"[HandleEnumDef] Unhandled kind in switch: '{_}'");
			}
		}

		return def;
	}

	public TypeAliasDef HandleTypedef(StringView name, JSONReader.JObject object, JSONReader.JArray inner)
	{
		Runtime.Assert(name.Length > 0);

		let referenced = object["isReferenced"].GetValueOrDefault().AsBool.GetValueOrDefault();

		if (!_aliasMap.TryAddAlt(name, let keyPtr, let valPtr))
		{
			return *valPtr;
		}

		TypeAliasDef def = new:alloc .();
		def.name.Set(name);

		*keyPtr = def.name;
		*valPtr = def;

		let type = object["type"].GetValueOrDefault().AsObject.GetValueOrDefault();
		ResolveType(type, def.alias);

		return def;
	}

	void HandleParamDecl(FunctionTypeDef def, JSONReader.JObject object)
	{
		let name = object["name"].GetValueOrDefault().AsString.GetValueOrDefault();
		let type = object["type"].GetValueOrDefault().AsObject.GetValueOrDefault();
		let decl = new:alloc VariableDecl();
		if (name != null)
			decl.name.Set(name);
		ResolveType(type, decl.type);

		def.args.Add(decl);
	}

	public FunctionTypeDef HandleFunction(StringView name, JSONReader.JObject object, JSONReader.JArray inner)
	{
		Runtime.Assert(name.Length > 0);

		let isImplicit = object["isImplicit"].GetValueOrDefault().AsBool.GetValueOrDefault();
		let isInline = object["inline"].GetValueOrDefault().AsBool.GetValueOrDefault();

		if (isImplicit || isInline)
			return null;

		let storageClass = object["storageClass"].GetValueOrDefault().AsString.GetValueOrDefault();
		
		if (_types.TryAddAlt(name, let keyPtr, let valPtr) == false)
		{
			Runtime.Assert((*valPtr) is FunctionTypeDef);
			return (FunctionTypeDef)(*valPtr);
		}
		
		let variadic = object["variadic"].GetValueOrDefault().AsBool.GetValueOrDefault();

		let def = new:alloc FunctionTypeDef();
		_functions.Add(def);

		def.name.Set(name);
		*keyPtr = def.name;
		*valPtr = def;

		def.storageKind = EStorageClassKind.FromString(storageClass);
		def.isVarArg = variadic;

		ResolveType(object["type"].Value.AsObject, def.functionType);
		ResultTypeFromFunctionType(def.functionType, def.resultType);

		LOOP:
		for (let v in inner)
		{
			let obj = v.AsObject.GetValueOrDefault();
			if (obj == null)
				continue;

			let kindString = obj["kind"].GetValueOrDefault().AsString.GetValueOrDefault();
			EDeclKind kind;
			switch (EDeclKind.FromString(kindString))
			{
			case .Ok(let val):
				{
					kind = val;
				}
			case .Err:
				{
					HANDLE_ATTR:
					do
					{
						switch (EDeclAttr.FromString(kindString))
						{
						case .Ok(let attr):
							{
								def.attrs.Add(attr);

								switch (attr)
								{
								case .DeprecatedAttr:
									def.isDeprecated = true;
								case .BuiltinAttr:
									def.isBuiltIn = true;
								case .ConstAttr:
									def.isConst = true;
								case .MSAllocatorAttr:
									def.isMSAlloc = true;

								case .NoThrowAttr, .AllocSizeAttr,
									 .FormatAttr, .AnalyzerNoReturnAttr,
									 .ReturnsTwiceAttr, .DLLImportAttr,
									 .NonNullAttr, .WarnUnusedResultAttr,
									 .RestrictAttr:

								case .MaxFieldAlignmentAttr, .TypeVisibilityAttr, .AlignedAttr:
									{
										Runtime.Assert(false);
									}
									
								/*default:
									break HANDLE_ATTR;*/
								}
								continue LOOP;
							}
						case .Err:
							break HANDLE_ATTR;
						}
					}

					Console.WriteLine($"HandleFunction unknown kind: {kindString}");
					continue LOOP;
				}
			}

			switch (kind)
			{
			case .FullComment, .TextComment, .ParagraphComment, .BlockCommandComment, .ParamCommandComment, .InlineCommandComment:
				{

				}
			case .ParmVarDecl:
				{
					HandleParamDecl(def, obj);
				}
			default:
				{
					Console.WriteLine($"HandleFunction kind unhandled: {_}");
					continue;
				}
			}
		}

		return def;
	}

	bool ResolveType(JSONReader.JObject object, TypeRef result)
	{
		Runtime.Assert(result.raw == null);

		if (let desugared = object["desugaredQualType"].GetValueOrDefault().AsString.GetValueOrDefault())
		{
			result.raw = new:alloc .(desugared);
			return true;
		}

		if (let qualType = object["qualType"].GetValueOrDefault().AsString.GetValueOrDefault())
		{
			result.raw = new:alloc .(qualType);
			return true;
		}

		Runtime.FatalError();
	}

	public Result<void> ResultTypeFromFunctionType(TypeRef fn, TypeRef result)
	{
		// this wont handle cases where functions return function pointers

		let parentIdx = fn.raw.IndexOf('(');
		if (parentIdx == -1)
			return .Err;

		Runtime.Assert(result.raw == null);
		result.raw = new:alloc .(fn.raw.Substring(0, parentIdx));
		return .Ok;
	}

	VariableDecl HandleFieldDecl(StructTypeDef def, JSONReader.JObject object)
	{
		let name = object["name"].GetValueOrDefault().AsString.GetValueOrDefault();
		let isReferenced = object["isReferenced"].GetValueOrDefault().AsBool.GetValueOrDefault();
		let typeObj = object["type"].GetValueOrDefault().AsObject.GetValueOrDefault();

		VariableDecl field = new:alloc .();
		field.name.Set(name);

		ResolveType(typeObj, field.type);
		def.fields.Add(field);
		return field;
	}

	public StructTypeDef HandleRecord(StringView name, JSONReader.JObject object, JSONReader.JArray inner, bool isInnerType = false)
	{
		Runtime.Assert(name.Length > 0);

		String* keyPtr = ?;
		TypeDef* valPtr = ?;
		if (!isInnerType)
		{
			if (_types.TryAddAlt(name, out keyPtr, out valPtr) == false)
			{
				Runtime.Assert((*valPtr) is StructTypeDef);
				return (StructTypeDef)(*valPtr);
			}
		}
		
		let tagString = object["tagUsed"].GetValueOrDefault().AsString.GetValueOrDefault();

		let def = new:alloc StructTypeDef();
		def.name.Set(name);

		if (!isInnerType)
		{
			_structs.Add(def);
			*keyPtr = def.name;
			*valPtr = def;
		}

		def.isCompleteDef = object["completeDefinition"].GetValueOrDefault().AsBool.GetValueOrDefault();

		switch (StructTypeDef.ETag.FromString(tagString))
		{
		case .Ok(out def.tag):
		case .Err:
			{
				def.tag = .Unknown;
				Console.WriteLine($"Unknown record tag: {tagString}");
			}
		}

		TypeDef prevTypedef = null;

		for (let v in inner)
		{
			let obj = v.AsObject.GetValueOrDefault();
			if (obj == null)
				continue;

			let kindString = obj["kind"].GetValueOrDefault().AsString.GetValueOrDefault();
			EDeclKind kind;
			switch (EDeclKind.FromString(kindString))
			{
			case .Ok(out kind):
			case .Err:
				{
					HANDLE_ATTR:
					switch (EDeclAttr.FromString(kindString))
					{
					case .Ok(let attr):
						{
							switch (attr)
							{
							case .MaxFieldAlignmentAttr:
								{
									bool isImplicit = obj["implicit"].GetValueOrDefault().AsBool.GetValueOrDefault();
									Runtime.Assert(isImplicit);
								}
							case .AlignedAttr:
								{

								}

							case .TypeVisibilityAttr:
								{

								}

							default:
								{
									break HANDLE_ATTR;
								}
							}

							continue;
						}
					case .Err:
					}

					Console.WriteLine($"HandleRecord unknown kind: {kindString}");
					continue;
				}
			}

			switch (kind)
			{
			case .FullComment, .TextComment, .ParagraphComment, .BlockCommandComment, .ParamCommandComment, .InlineCommandComment:
				{

				}

			case .FieldDecl:
				{
					let field = HandleFieldDecl(def, obj);

					if (prevTypedef != null)
					{
						prevTypedef.name..Clear()..AppendF($"{field.name}_T")..ToUpper();

						if (field.type.raw.Contains("unnamed"))
						{
							field.type.raw.Set(prevTypedef.name);
						}

						prevTypedef = null;
					}
					
				}

			case .RecordDecl:
				{
					let nameValue = obj["name"].GetValueOrDefault().AsString.GetValueOrDefault();
					String subName = scope .();

					subName.Append(def.name);
					subName.Append(".");

					let tag = obj["tagUsed"].GetValueOrDefault().AsString.GetValueOrDefault();
					if (String.IsNullOrEmpty(nameValue))
					{
						if (String.IsNullOrEmpty(tag))
							subName.Append("unknown");
						else
							subName.Append(tag);

						let loc = obj["loc"].GetValueOrDefault().AsObject.GetValueOrDefault();
						if (loc != null)
						{
							if (loc["line"].GetValueOrDefault().AsInt64 case .Ok(let line) && loc["col"].GetValueOrDefault().AsInt64 case .Ok(let col))
								subName.AppendF($":{line}:{col}");
						}

					}
					else
					{
						subName.Append(nameValue);
					}

					let innerArr = obj["inner"].GetValueOrDefault().AsArray.GetValueOrDefault();

					def.innerTypes ??= new:alloc .();
					
					let type = HandleRecord(subName, obj, innerArr, true);
					def.innerTypes.Add(type);

					prevTypedef = type;
				}

			default:
				{
					Console.WriteLine($"HandleRecord kind unhandled: {_}");
					continue;
				}
			}

		}

		return def;
	}

	public GlobalVariableDecl HandleVariable(StringView name, JSONReader.JObject object, JSONReader.JArray inner)
	{
		Runtime.Assert(name.Length > 0);

		let storageClass = object["storageClass"].GetValueOrDefault().AsString.GetValueOrDefault();

		let decl = new:this GlobalVariableDecl();
		decl.name.Set(name);
		decl.storageKind = .FromString(storageClass);
		let type = object["type"].GetValueOrDefault().AsObject.GetValueOrDefault();
		ResolveType(type, decl.type);

		globalVars.Add(decl);
		return decl;
	}

	public void* Alloc(int size, int align) => alloc.Alloc(size, align);

	public void Free(void* ptr) => alloc.Free(ptr);

	public void* AllocTyped(Type type, int size, int align)
	{
#if BF_ENABLE_REALTIME_LEAK_CHECK
		return alloc.AllocTyped(type, size, align);
#else
		return Alloc(size, align);
#endif

	}
}