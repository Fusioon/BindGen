using System;
namespace JSONReader
{
	enum JValue /*: IDisposable*/
	{
		case NULL;
		case BOOL(bool v);
		case INT64(int64 v);
		case DOUBLE(double v);
		case STRING(String v);
		case ARRAY(JArray v);
		case OBJECT(JObject v);

		public void Free<TAlloc>(TAlloc alloc) where TAlloc : IRawAllocator, class
		{
			switch (this)
			{
			case .NULL, .BOOL, .INT64, .DOUBLE:
				break;

			case .STRING(let v):
				delete:alloc v;
			case .OBJECT(let v):
				v.Free(alloc);
				delete:alloc v;
			case .ARRAY(let v):
				v.Free(alloc);
				delete:alloc v;
			}
		}

		public Result<bool> AsBool
		{
			get
			{
				switch(this)
				{
				case .BOOL(let v):	return v;
				case .INT64(let v):	return v != 0 ? true : false;
				case .DOUBLE(let v): return v != 0 ? true : false;
				case .STRING, .ARRAY, .OBJECT, .NULL: break;
				}
				return .Err;
			}
		}

		public Result<int32> AsInt32
		{
			get
			{
				switch(this)
				{
				case .BOOL(let v):	return v ? 1 : 0;
				case .INT64(let v):	return (int32)v;
				case .DOUBLE(let v): return (int32)v;
				case .STRING, .ARRAY, .OBJECT, .NULL: break;
				}
				return .Err;
			}
		}

		public Result<int64> AsInt64
		{
			get
			{
				switch(this)
				{
				case .BOOL(let v):	return v ? 1 : 0;
				case .INT64(let v):	return v;
				case .DOUBLE(let v): return (int64)v;
				case .STRING, .ARRAY, .OBJECT, .NULL: break;
				}
				return .Err;
			}
		}

		public Result<float> AsFloat
		{
			get
			{
				switch(this)
				{
				case .BOOL(let v):	return v ? 1 : 0;
				case .INT64(let v):	return (float)v;
				case .DOUBLE(let v): return (float)v;
				case .STRING, .ARRAY, .OBJECT, .NULL: break;
				}
				return .Err;
			}
		}

		public Result<double> AsDouble
		{
			get
			{
				switch(this)
				{
				case .BOOL(let v):	return v ? 1 : 0;
				case .INT64(let v):	return (double)v;
				case .DOUBLE(let v): return v;
				case .STRING, .ARRAY, .OBJECT, .NULL: break;
				}
				return .Err;
			}
		}

		public Result<String> AsString
		{
			get
			{
				switch(this)
				{
				case .NULL: return .Ok(null);

				case .STRING(let v): return v;
				case .BOOL, .INT64, .DOUBLE, .ARRAY, .OBJECT: break;
				}
				return .Err;
			}
		}

		public Result<JObject> AsObject
		{
			get
			{
				switch(this)
				{
				case .NULL: return .Ok(null);

				case .OBJECT(let v): return v;
				case .BOOL, .INT64, .DOUBLE, .ARRAY, .STRING: break;
				}
				return .Err;
			}
		}

		public Result<JArray> AsArray
		{
			get
			{
				switch(this)
				{
				case .NULL: return .Ok(null);

				case .ARRAY(let v): return v;
				case .BOOL, .INT64, .DOUBLE, .OBJECT, .STRING: break;
				}
				return .Err;
			}
		}

		public static explicit operator bool(Self v) => v.AsBool.GetValueOrDefault();
		public static explicit operator int32(Self v) => v.AsInt32.GetValueOrDefault();
		public static explicit operator int64(Self v) => v.AsInt64.GetValueOrDefault();
		public static explicit operator String(Self v) => v.AsString.GetValueOrDefault();
		public static explicit operator StringView(Self v) => v.AsString.GetValueOrDefault();
	}
}
