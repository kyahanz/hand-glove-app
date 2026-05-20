# ╔══════════════════════════════════════════════════════════════════╗
# ║         BISINDO NN Training — Google Colab Version             ║
# ║  Jalankan cell per cell dari atas ke bawah                     ║
# ╚══════════════════════════════════════════════════════════════════╝

# ── Cell 1: Install dependencies ───────────────────────────────────
# !pip install -q scipy scikit-learn


# ── Cell 2: Import ─────────────────────────────────────────────────
import glob, json, os, zipfile, io
import numpy as np
import pandas as pd
from scipy.spatial.transform import Rotation
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import tensorflow as tf
from tensorflow import keras
from google.colab import files

print('TF version:', tf.__version__)


# ── Cell 3: Upload CSV ─────────────────────────────────────────────
# Upload semua file CSV dataset kamu (bisa pilih banyak sekaligus)
uploaded = files.upload()   # ← klik tombol "Choose Files"

# Gabungkan semua CSV yang di-upload
dfs = []
for fname, content in uploaded.items():
    if fname.endswith('.csv'):
        dfs.append(pd.read_csv(io.BytesIO(content)))

X = pd.concat(dfs, ignore_index=True)
print(f'Total sampel: {len(X)}')
print(f'Kolom: {list(X.columns)}')


# ── Cell 4: Preprocessing (sama persis alur MATLAB) ───────────────

# Y = X.label;
Y = X['label']

# X = X(:, setdiff(ds.VariableNames, {'timestamp','hand_w','hand_x','hand_y','hand_z','label'}));
drop_cols = ['timestamp', 'hand_w', 'hand_x', 'hand_y', 'hand_z', 'label']
X = X.drop(columns=[c for c in drop_cols if c in X.columns])

# X.indexQ = rad2deg(quat2eul(quaternion(w,x,y,z), 'ZYX'));
# MATLAB: quaternion(w,x,y,z) → scipy: from_quat([x,y,z,w])  ← scalar terakhir
def quat_to_euler_zyx_deg(df, prefix):
    quats = np.stack([
        df[f'{prefix}_x'].values,
        df[f'{prefix}_y'].values,
        df[f'{prefix}_z'].values,
        df[f'{prefix}_w'].values,
    ], axis=1)
    return Rotation.from_quat(quats).as_euler('ZYX', degrees=True)

X[['indexQ_z',  'indexQ_y',  'indexQ_x']]  = quat_to_euler_zyx_deg(X, 'index_mcp')
X[['middleQ_z', 'middleQ_y', 'middleQ_x']] = quat_to_euler_zyx_deg(X, 'middle_mcp')
X[['ringQ_z',   'ringQ_y',   'ringQ_x']]   = quat_to_euler_zyx_deg(X, 'ring_mcp')
X[['pinkyQ_z',  'pinkyQ_y',  'pinkyQ_x']]  = quat_to_euler_zyx_deg(X, 'pinky_mcp')
X[['thumbQ_z',  'thumbQ_y',  'thumbQ_x']]  = quat_to_euler_zyx_deg(X, 'thumb_mcp')

# cols = ["index_dip" "index_pip" "indexQ" ... "thumb_ip" "thumbQ"];
# X_train = X{:, cols};
COLS = [
    'index_dip',  'index_pip',  'indexQ_z',  'indexQ_y',  'indexQ_x',
    'middle_dip', 'middle_pip', 'middleQ_z', 'middleQ_y', 'middleQ_x',
    'ring_dip',   'ring_pip',   'ringQ_z',   'ringQ_y',   'ringQ_x',
    'pinky_dip',  'pinky_pip',  'pinkyQ_z',  'pinkyQ_y',  'pinkyQ_x',
    'thumb_ip',                 'thumbQ_z',  'thumbQ_y',  'thumbQ_x',
]
X_feat = X[COLS].values.astype(np.float32)

le = LabelEncoder()
Y_enc = le.fit_transform(Y)
num_classes = len(le.classes_)
print(f'Kelas ({num_classes}): {list(le.classes_)}')

# X_scaled = (X - mean(X)) ./ std(X);
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_feat)

X_tr, X_val, y_tr, y_val = train_test_split(
    X_scaled, Y_enc, test_size=0.2, random_state=42, stratify=Y_enc
)
print(f'Train: {len(X_tr)} | Val: {len(X_val)}')


# ── Cell 5: Bangun & train Neural Network ──────────────────────────

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

model.fit(
    X_tr, y_tr,
    epochs=100,
    batch_size=32,
    validation_data=(X_val, y_val),
    callbacks=[
        keras.callbacks.EarlyStopping(monitor='val_accuracy', patience=15, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(monitor='val_loss', patience=7, factor=0.5, verbose=1),
    ],
)

loss, acc = model.evaluate(X_val, y_val, verbose=0)
print(f'\nVal accuracy : {acc:.4f}')
print(f'Val loss     : {loss:.4f}')


# ── Cell 6: Export TFLite ──────────────────────────────────────────

converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

with open('bisindo_nn_model.tflite', 'wb') as f:
    f.write(tflite_model)
print(f'TFLite size: {len(tflite_model) / 1024:.1f} KB')


# ── Cell 7: Simpan scaler params & labels ─────────────────────────

scaler_params = {
    'scaler_type'  : 'StandardScaler',
    'mean'         : scaler.mean_.tolist(),
    'scale'        : scaler.scale_.tolist(),
    'feature_names': COLS,
    'note'         : f'{len(X_tr)+len(X_val)} samples, {num_classes} classes',
}
with open('scaler_params_nn.json', 'w') as f:
    json.dump(scaler_params, f, indent=2)

with open('nn_labels.json', 'w') as f:
    json.dump({'labels': le.classes_.tolist()}, f, indent=2)

print('Semua file tersimpan.')


# ── Cell 8: Download semua file sekaligus ──────────────────────────

# Zip semua output jadi satu file
with zipfile.ZipFile('bisindo_model_output.zip', 'w') as zf:
    zf.write('bisindo_nn_model.tflite')
    zf.write('scaler_params_nn.json')
    zf.write('nn_labels.json')

files.download('bisindo_model_output.zip')
print('Download dimulai!')
