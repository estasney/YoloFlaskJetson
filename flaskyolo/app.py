from flask import Flask, request, jsonify, render_template
from yolov5.models.slim import SlimModelRunner
from PIL import Image, ImageDraw
import numpy as np
import base64
from io import BytesIO
import os

app = Flask(__name__)
model = SlimModelRunner(weights=os.path.join(app.root_path, "model/model.pt"), device='cuda')
image_cache = {}


def draw_predict(img, pred):
    img = Image.fromarray(img.astype(np.uint8))
    for detect in pred['detections']:
        box = detect['xyxy']
        cls = detect['cls']
        confidence = detect['confidence']

        print(cls, confidence)
        ImageDraw.Draw(img).rectangle(box, width=4, outline='red')  # plot

    with BytesIO() as output:
        img.save(output, format="JPEG")
        contents = output.getvalue()

    return contents


@app.route('/current/<channel>', methods=['GET'])
def imgdraw_channel(channel):
    img_data = image_cache.get(channel)
    if not img_data:
        return jsonify({"message": "error"}), 404
    img = img_data['img']
    pred = {k: v for k, v in img_data.items() if k != 'img'}

    drawn = draw_predict(img, pred)
    img_b64 = base64.b64encode(drawn)
    img_b64 = img_b64.decode('utf-8')

    return render_template("result.html", img=img_b64)


@app.route('/')
def hello_world():
    return render_template("upload.html")


@app.route('/api', methods=['POST'])
def api_predict():
    img_tasks = []

    for img_name, img_file in request.files.items():
        img_arr = np.array(Image.open(img_file))
        img_tasks.append((img_name, img_arr))

    predictions = model.detect([img for img_name, img in img_tasks])

    data_response = []

    for (img_name, img_arr), img_pred in zip(img_tasks, predictions):
        data_response.append({'img_id': img_name, **img_pred})
        image_cache[img_name] = {'img': img_arr.astype(np.uint8), **img_pred}

    return jsonify(data_response), 200


@app.route('/imgdraw', methods=['POST'])
def imgdraw():
    f = request.files['file']
    img = [np.array(Image.open(f))]
    pred = model.detect(img)[0]

    img_data = draw_predict(img[0], pred)
    img_b64 = base64.b64encode(img_data)
    img_b64 = img_b64.decode('utf-8')

    return render_template("result.html", img=img_b64)


if __name__ == '__main__':
    app.run()
