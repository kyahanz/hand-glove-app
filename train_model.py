"""
Train BISINDO gesture NN model from CSV datasets.
Alur sama persis dengan MATLAB, hanya KNN diganti Neural Network.

Usage:
    python train_model.py --data ./path/to/csv/folder
    python train_model.py --data ./path/to/csv/folder --epochs 150
"""

import argparse
import glob
import json
import os

import numpy as np
import pandas as pd
from scipy.spatial.transform import Rotation
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import tensorflow as tf
from tensorflow import keras

# ── Args ───────────────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument('--data',   required=True, help='Folder berisi file CSV dataset')
parser.add_argument('--epochs', type=int, default=100)
parser.add_argument('--out',    default='./assets', help='Folder output hasil training')
args = parser.parse_args()

os.makedirs(args.out, exist_ok=True)

# ── 1. Load CSV  ───────────────────────────────────────────────────
# ds = datastore("./assets/datasets/nn/*.csv");
# X  = readall(ds);
files = glob.glob(os.path.join(args.data, '**', '*.csv'), recursive=True)
if not files:
    files = glob.glob(os.path.join(args.data, '*.csv'))

if not files:
    raise FileNotFoundError(f'Tidak ada file CSV di: {args.data}')

print(f'[INFO] Ditemukan {len(files)} file CSV')
X = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
print(f'[INFO] Total sampel: {len(X)}')

# ── 2. Pisahkan label ──────────────────────────────────────────────
# Y = X.label;
Y = X['label']

# X = X(:, setdiff(ds.VariableNames, {'timestamp','hand_w','hand_x','hand_y','hand_z','label'}));
drop_cols = ['timestamp', 'hand_w', 'hand_x', 'hand_y', 'hand_z', 'label']
X = X.drop(columns=[c for c in drop_cols if c in X.columns])

# ── 3. Quaternion → Euler ZYX (degrees) per jari ──────────────────
# X.indexQ = rad2deg(quat2eul(quaternion(w,x,y,z), 'ZYX'));
# MATLAB: quaternion(w,x,y,z) → scipy from_quat([x,y,z,w])  ← scalar terakhir
def quat_to_euler_zyx_deg(df, prefix):
    quats = np.stack([
        df[f'{prefix}_x'].values,
        df[f'{prefix}_y'].values,
        df[f'{prefix}_z'].values,
        df[f'{prefix}_w'].values,
    ], axis=1)
    return Rotation.from_quat(quats).as_euler('ZYX', degrees=True)  # → [Z, Y, X]

X[['indexQ_z',  'indexQ_y',  'indexQ_x']]  = quat_to_euler_zyx_deg(X, 'index_mcp')
X[['middleQ_z', 'middleQ_y', 'middleQ_x']] = quat_to_euler_zyx_deg(X, 'middle_mcp')
X[['ringQ_z',   'ringQ_y',   'ringQ_x']]   = quat_to_euler_zyx_deg(X, 'ring_mcp')
X[['pinkyQ_z',  'pinkyQ_y',  'pinkyQ_x']]  = quat_to_euler_zyx_deg(X, 'pinky_mcp')
X[['thumbQ_z',  'thumbQ_y',  'thumbQ_x']]  = quat_to_euler_zyx_deg(X, 'thumb_mcp')

# ── 4. Pilih fitur  ────────────────────────────────────────────────
# cols = ["index_dip" "index_pip" "indexQ" ... "thumb_ip" "thumbQ"];
# X_train = X{:, cols};
# Di MATLAB, kolom indexQ (Nx3) otomatis expand → total 24 fitur
COLS = [
    'index_dip',  'index_pip',  'indexQ_z',  'indexQ_y',  'indexQ_x',
    'middle_dip', 'middle_pip', 'middleQ_z', 'middleQ_y', 'middleQ_x',
    'ring_dip',   'ring_pip',   'ringQ_z',   'ringQ_y',   'ringQ_x',
    'pinky_dip',  'pinky_pip',  'pinkyQ_z',  'pinkyQ_y',  'pinkyQ_x',
    'thumb_ip',                 'thumbQ_z',  'thumbQ_y',  'thumbQ_x',
]
X_train = X[COLS].values.astype(np.float32)

# ── 5. Encode label ────────────────────────────────────────────────
le = LabelEncoder()
Y_enc = le.fit_transform(Y)
num_classes = len(le.classes_)
print(f'[INFO] Kelas: {list(le.classes_)}  ({num_classes} kelas)')

# ── 6. Normalisasi  ────────────────────────────────────────────────
# X_scaled = (X - mean(X)) ./ std(X);  ← di MATLAB di-comment, NN wajib pakai
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_train)

# ── 7. Split train / validation ────────────────────────────────────
X_tr, X_val, y_tr, y_val = train_test_split(
    X_scaled, Y_enc,
    test_size=0.2,
    random_state=42,
    stratify=Y_enc,
)

# ── 8. Bangun Neural Network ───────────────────────────────────────
# Ganti: cv_mdl = fitcknn(X_train, Y_train, 'NumNeighbors', 3, 'Distance', 'euclidean');
model = keras.Sequential([
    keras.layers.Input(shape=(len(COLS),)),
    keras.layers.Dense(128, activation='relu'),
    keras.layers.Dropout(0.3),
    keras.layers.Dense(64, activation='relu'),
    keras.layers.Dropout(0.2),
    keras.layers.Dense(32, activation='relu'),
    keras.layers.Dense(num_classes, activation='softmax'),
], name='bisindo_nn')

model.compile(
    optimizer='adam',
    loss='sparse_categorical_crossentropy',
    metrics=['accuracy'],
)
model.summary()

# ── 9. Training ────────────────────────────────────────────────────
history = model.fit(
    X_tr, y_tr,
    epochs=args.epochs,
    batch_size=32,
    validation_data=(X_val, y_val),
    callbacks=[
        keras.callbacks.EarlyStopping(monitor='val_accuracy', patience=15, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(monitor='val_loss', patience=7, factor=0.5, verbose=1),
    ],
    verbose=1,
)

# ── 10. Evaluasi ───────────────────────────────────────────────────
loss, acc = model.evaluate(X_val, y_val, verbose=0)
print(f'\n[RESULT] Val accuracy : {acc:.4f}')
print(f'[RESULT] Val loss     : {loss:.4f}')

# ── 11. Export ke TFLite ───────────────────────────────────────────
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

tflite_path = os.path.join(args.out, 'bisindo_nn_model.tflite')
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)
print(f'[SAVED] TFLite  → {tflite_path}')

# ── 12. Simpan scaler params (dipakai Flutter untuk preprocessing) ─
scaler_path = os.path.join(args.out, 'scaler_params_nn.json')
scaler_params = {
    'scaler_type'   : 'StandardScaler',
    'mean'          : scaler.mean_.tolist(),
    'scale'         : scaler.scale_.tolist(),
    'feature_names' : COLS,
    'note'          : f'{len(X_tr)+len(X_val)} samples, {num_classes} classes',
}
with open(scaler_path, 'w') as f:
    json.dump(scaler_params, f, indent=2)
print(f'[SAVED] Scaler  → {scaler_path}')

# ── 13. Simpan label classes ───────────────────────────────────────
labels_path = os.path.join(args.out, 'nn_labels.json')
labels_data = {'labels': le.classes_.tolist()}
with open(labels_path, 'w') as f:
    json.dump(labels_data, f, indent=2)
print(f'[SAVED] Labels  → {labels_path}')

print('\nDone! File siap dipakai di Flutter.')
