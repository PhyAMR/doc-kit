# A script run as a whole (%run or exec); it leaves `result` behind.
import numpy as np

values = np.arange(1, 6)
result = values.sum()
print(f"script.py ran: sum of {values.tolist()} = {result}")
