table.insert(props,{
  Name = 'Component Count',
  Type = 'integer',
  Min = 1,
  Max = 255,
  Value = 2
})
table.insert(props,{
  Name    = "Debug Print",
  Type    = "enum",
  Choices = {"None", "Tx/Rx", "Tx", "Rx", "Function Calls", "All"},
  Value   = "None"
})