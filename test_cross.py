import numpy as np

def cross(v1, v2, v3, v4):
    v1, v2, v3, v4 = map(np.array, (v1, v2, v3, v4))
    d0 = np.cross(v2 - v1, v3 - v4)
    d1 = np.cross(v3 - v1, v3 - v4) / d0
    d2 = np.cross(v2 - v1, v3 - v1) / d0
    v = v1 + d1 * (v2 - v1)
    assert np.allclose(v, v3 + d2 * (v4 - v3))
    return v

assert np.allclose(np.array([1, 1]), cross((0, 0), (2, 2), (0, 2), (2, 0)))

for t in range(1000):
    cross(*(np.random.rand(2) for i in range(4)))
