using System;
using System.Collections;

namespace JSONReader
{
	class JArray : IEnumerable<JValue>
	{
		public void Free<TAlloc>(TAlloc alloc) where TAlloc : IRawAllocator, class
		{
			for (let v in _values)
			{
				v.Free(alloc);
			}
			_values.Clear();
		}

		append List<JValue> _values;
		public int Count => _values.Count;
		public bool IsEmpty => _values.IsEmpty;

		public JValue this[int i]
		{
			get => _values[i];
		}	

		internal void AddValue(JValue val)
		{
			_values.Add(val);
		}

		public List<JValue>.Enumerator GetEnumerator()
		{
			return _values.GetEnumerator();
		}

	}
}
