const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

const bundledNodeModules =
  process.env.CODEX_NODE_MODULES ||
  'C:/Users/10562/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';

function requireBundledPackage(packageName) {
  const pnpmDir = path.join(bundledNodeModules, '.pnpm');
  if (fs.existsSync(pnpmDir)) {
    const match = fs
      .readdirSync(pnpmDir)
      .find((entry) => entry === packageName || entry.startsWith(`${packageName}@`));
    if (match) {
      return createRequire(
        path.join(pnpmDir, match, 'node_modules', packageName, 'package.json'),
      )(packageName);
    }
  }

  const directPackageJson = path.join(
    bundledNodeModules,
    packageName,
    'package.json',
  );
  if (fs.existsSync(directPackageJson)) {
    return createRequire(directPackageJson)(packageName);
  }

  throw new Error(`Cannot locate bundled package ${packageName}`);
}

const { chromium } = requireBundledPackage('playwright');
const { PNG } = requireBundledPackage('pngjs');

const outputDir = path.resolve(process.argv[2] || 'build/diagnostics/nai_inpaint_parity');
const width = 256;
const height = 192;

function findBrowserExecutable() {
  const candidates = [
    process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate));
}

function readDataUrl(name) {
  return `data:image/png;base64,${fs.readFileSync(path.join(outputDir, name)).toString('base64')}`;
}

function writeBase64Png(name, base64) {
  fs.writeFileSync(path.join(outputDir, name), Buffer.from(base64, 'base64'));
}

function readPng(name) {
  return PNG.sync.read(fs.readFileSync(path.join(outputDir, name)));
}

function writePng(name, png) {
  fs.writeFileSync(path.join(outputDir, name), PNG.sync.write(png));
}

function comparePngs(actualName, expectedName, heatName) {
  const actual = readPng(actualName);
  const expected = readPng(expectedName);
  if (actual.width !== expected.width || actual.height !== expected.height) {
    throw new Error(
      `${actualName} and ${expectedName} dimensions differ: ` +
        `${actual.width}x${actual.height} vs ${expected.width}x${expected.height}`,
    );
  }

  const heat = new PNG({ width: actual.width, height: actual.height });
  const maxDiffs = [];
  let maxChannel = 0;
  let sumAbsRgba = 0;
  let sumAbsRgb = 0;
  let sumSqRgb = 0;
  let nonZeroPixels = 0;
  let exactPixels = 0;
  let minX = actual.width;
  let minY = actual.height;
  let maxX = -1;
  let maxY = -1;

  for (let y = 0; y < actual.height; y++) {
    for (let x = 0; x < actual.width; x++) {
      const idx = (y * actual.width + x) * 4;
      let pixelMax = 0;
      let pixelAny = false;
      for (let c = 0; c < 4; c++) {
        const diff = Math.abs(actual.data[idx + c] - expected.data[idx + c]);
        sumAbsRgba += diff;
        pixelMax = Math.max(pixelMax, diff);
        maxChannel = Math.max(maxChannel, diff);
        if (c < 3) {
          sumAbsRgb += diff;
          sumSqRgb += diff * diff;
        }
        if (diff !== 0) {
          pixelAny = true;
        }
      }

      if (pixelAny) {
        nonZeroPixels++;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      } else {
        exactPixels++;
      }
      maxDiffs.push(pixelMax);

      const visible = Math.min(255, pixelMax * 10);
      heat.data[idx] = visible;
      heat.data[idx + 1] = pixelMax === 0 ? 0 : Math.max(0, 80 - visible / 4);
      heat.data[idx + 2] = pixelMax === 0 ? 0 : 255 - visible;
      heat.data[idx + 3] = 255;
    }
  }

  maxDiffs.sort((a, b) => a - b);
  writePng(heatName, heat);

  const pixels = actual.width * actual.height;
  const channels = pixels * 4;
  const rgbChannels = pixels * 3;
  const percentile = (p) => maxDiffs[Math.min(maxDiffs.length - 1, Math.floor(maxDiffs.length * p))];
  return {
    actual: actualName,
    expected: expectedName,
    heatmap: heatName,
    pixels,
    exactPixelPercent: Number(((exactPixels / pixels) * 100).toFixed(4)),
    nonZeroPixelPercent: Number(((nonZeroPixels / pixels) * 100).toFixed(4)),
    maxChannel,
    meanAbsRgba: Number((sumAbsRgba / channels).toFixed(6)),
    meanAbsRgb: Number((sumAbsRgb / rgbChannels).toFixed(6)),
    rmseRgb: Number(Math.sqrt(sumSqRgb / rgbChannels).toFixed(6)),
    p95MaxChannel: percentile(0.95),
    p99MaxChannel: percentile(0.99),
    diffBounds:
      maxX < 0
        ? null
        : {
            minX,
            minY,
            maxX,
            maxY,
          },
  };
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });

  const executablePath = findBrowserExecutable();
  const browser = await chromium.launch({
    headless: true,
    ...(executablePath ? { executablePath } : {}),
  });
  const page = await browser.newPage();
  const official = await page.evaluate(
    async ({
      sourceUrl,
      generatedUrl,
      maskUrl,
      localCompositeMaskUrl,
      width,
      height,
    }) => {
      const mulTable = new Uint8Array([
        1, 57, 41, 21, 203, 34, 97, 73, 227, 91, 149, 62, 105, 45, 39, 137,
        241, 107, 3, 173, 39, 71, 65, 238, 219, 101, 187, 87, 81, 151, 141,
        133, 249, 117, 221, 209, 197, 187, 177, 169, 5, 153, 73, 139, 133,
        127, 243, 233, 223, 107, 103, 99, 191, 23, 177, 171, 165, 159, 77,
        149, 9, 139, 135, 131, 253, 245, 119, 231, 224, 109, 211, 103, 25,
        195, 189, 23, 45, 175, 171, 83, 81, 79, 155, 151, 147, 9, 141, 137,
        67, 131, 129, 251, 123, 30, 235, 115, 113, 221, 217, 53, 13, 51, 50,
        49, 193, 189, 185, 91, 179, 175, 43, 169, 83, 163, 5, 79, 155, 19,
        75, 147, 145, 143, 35, 69, 17, 67, 33, 65, 255, 251, 247, 243, 239,
        59, 29, 229, 113, 111, 219, 27, 213, 105, 207, 51, 201, 199, 49,
        193, 191, 47, 93, 183, 181, 179, 11, 87, 43, 85, 167, 165, 163, 161,
        159, 157, 155, 77, 19, 75, 37, 73, 145, 143, 141, 35, 138, 137, 135,
        67, 33, 131, 129, 255, 63, 250, 247, 61, 121, 239, 237, 117, 29,
        229, 227, 225, 111, 55, 109, 216, 213, 211, 209, 207, 205, 203, 201,
        199, 197, 195, 193, 48, 190, 47, 93, 185, 183, 181, 179, 178, 176,
        175, 173, 171, 85, 21, 167, 165, 41, 163, 161, 5, 79, 157, 78, 154,
        153, 19, 75, 149, 74, 147, 73, 144, 143, 71, 141, 140, 139, 137, 17,
        135, 134, 133, 66, 131, 65, 129, 1,
      ]);
      const shgTable = new Uint8Array([
        0, 9, 10, 10, 14, 12, 14, 14, 16, 15, 16, 15, 16, 15, 15, 17, 18,
        17, 12, 18, 16, 17, 17, 19, 19, 18, 19, 18, 18, 19, 19, 19, 20, 19,
        20, 20, 20, 20, 20, 20, 15, 20, 19, 20, 20, 20, 21, 21, 21, 20, 20,
        20, 21, 18, 21, 21, 21, 21, 20, 21, 17, 21, 21, 21, 22, 22, 21, 22,
        22, 21, 22, 21, 19, 22, 22, 19, 20, 22, 22, 21, 21, 21, 22, 22, 22,
        18, 22, 22, 21, 22, 22, 23, 22, 20, 23, 22, 22, 23, 23, 21, 19, 21,
        21, 21, 23, 23, 23, 22, 23, 23, 21, 23, 22, 23, 18, 22, 23, 20, 22,
        23, 23, 23, 21, 22, 20, 22, 21, 22, 24, 24, 24, 24, 24, 22, 21, 24,
        23, 23, 24, 21, 24, 23, 24, 22, 24, 24, 22, 24, 24, 22, 23, 24, 24,
        24, 20, 23, 22, 23, 24, 24, 24, 24, 24, 24, 24, 23, 21, 23, 22, 23,
        24, 24, 24, 22, 24, 24, 24, 23, 22, 24, 24, 25, 23, 25, 25, 23, 24,
        25, 25, 24, 22, 25, 25, 25, 24, 23, 24, 25, 25, 25, 25, 25, 25, 25,
        25, 25, 25, 25, 23, 25, 23, 24, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        24, 22, 25, 25, 23, 25, 25, 20, 24, 25, 24, 25, 25, 22, 24, 25, 24,
        25, 24, 25, 25, 24, 25, 25, 25, 25, 22, 25, 25, 25, 24, 25, 24, 25,
        18,
      ]);

      function loadImage(url) {
        return new Promise((resolve, reject) => {
          const image = new Image();
          image.onload = () => resolve(image);
          image.onerror = reject;
          image.src = url;
        });
      }

      function imageToData(image) {
        const canvas = document.createElement('canvas');
        canvas.width = image.naturalWidth;
        canvas.height = image.naturalHeight;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(image, 0, 0);
        return ctx.getImageData(0, 0, canvas.width, canvas.height);
      }

      function dataToPngBase64(imageData) {
        const canvas = document.createElement('canvas');
        canvas.width = imageData.width;
        canvas.height = imageData.height;
        canvas.getContext('2d').putImageData(imageData, 0, 0);
        return canvas.toDataURL('image/png').split(',')[1];
      }

      function resizeCanvas(imageData, dstWidth, dstHeight, smoothing) {
        const src = document.createElement('canvas');
        src.width = imageData.width;
        src.height = imageData.height;
        src.getContext('2d').putImageData(imageData, 0, 0);
        const dst = document.createElement('canvas');
        dst.width = dstWidth;
        dst.height = dstHeight;
        const ctx = dst.getContext('2d');
        ctx.imageSmoothingEnabled = smoothing;
        ctx.drawImage(src, 0, 0, dstWidth, dstHeight);
        return ctx.getImageData(0, 0, dstWidth, dstHeight);
      }

      function resizeOverBlack(imageData, dstWidth, dstHeight, smoothing) {
        const src = document.createElement('canvas');
        src.width = imageData.width;
        src.height = imageData.height;
        src.getContext('2d').putImageData(imageData, 0, 0);
        const dst = document.createElement('canvas');
        dst.width = dstWidth;
        dst.height = dstHeight;
        const ctx = dst.getContext('2d');
        ctx.fillStyle = 'black';
        ctx.fillRect(0, 0, dstWidth, dstHeight);
        ctx.imageSmoothingEnabled = smoothing;
        ctx.drawImage(src, 0, 0, dstWidth, dstHeight);
        return ctx.getImageData(0, 0, dstWidth, dstHeight);
      }

      function thresholdAlpha(imageData, threshold) {
        const out = new ImageData(imageData.width, imageData.height);
        for (let i = 0; i < imageData.data.length; i += 4) {
          const value = imageData.data[i + 3] > threshold ? 255 : 0;
          out.data[i] = value;
          out.data[i + 1] = value;
          out.data[i + 2] = value;
          out.data[i + 3] = value;
        }
        return out;
      }

      function replaceTransparent(imageData, color) {
        const data = new Uint8ClampedArray(imageData.data);
        for (let i = 0; i < data.length; i += 4) {
          if (data[i + 3] === 0) {
            data[i] = color[0];
            data[i + 1] = color[1];
            data[i + 2] = color[2];
            data[i + 3] = color[3];
          }
        }
        return new ImageData(data, imageData.width, imageData.height);
      }

      function dilate(imageData, radius, width, height) {
        const src = new Uint8ClampedArray(imageData.data);
        const dst = new Uint8ClampedArray(imageData.data.length);
        for (let i = 0; i < dst.length; i += 4) {
          dst[i + 3] = 255;
        }
        const stride = 4 * width;
        for (let y = 0; y < height; y++) {
          for (let x = 0; x < width; x++) {
            if (src[(y * width + x) * 4] === 255) {
              const minY = Math.max(0, y - radius);
              const maxY = Math.min(height, y + radius + 1);
              const minX = Math.max(0, x - radius);
              const maxX = Math.min(width, x + radius + 1);
              for (let yy = minY; yy < maxY; yy++) {
                const row = yy * stride;
                for (let xx = minX; xx < maxX; xx++) {
                  const idx = row + 4 * xx;
                  dst[idx] = 255;
                  dst[idx + 1] = 255;
                  dst[idx + 2] = 255;
                }
              }
            }
          }
        }
        for (let y = 0; y < height; y++) {
          for (let x = 0; x < width; x++) {
            const idx = (y * width + x) * 4;
            if (src[idx] === 255) continue;
            let hasWhite = false;
            const minY = Math.max(0, y - radius);
            const maxY = Math.min(height, y + radius + 1);
            const minX = Math.max(0, x - radius);
            const maxX = Math.min(width, x + radius + 1);
            for (let yy = minY; yy < maxY; yy++) {
              const row = yy * stride;
              for (let xx = minX; xx < maxX; xx++) {
                if (dst[row + 4 * xx] === 255) {
                  hasWhite = true;
                  break;
                }
              }
              if (hasWhite) break;
            }
            if (!hasWhite) {
              dst[idx] = 0;
              dst[idx + 1] = 0;
              dst[idx + 2] = 0;
            }
          }
        }
        return new ImageData(dst, width, height);
      }

      function linearScale(imageData, scale) {
        if (scale < 1) throw new Error('Scale must be greater than or equal to 1');
        if ((scale & (scale - 1)) !== 0) throw new Error('Scale must be a power of 2');
        const src = new Uint8ClampedArray(imageData.data);
        const srcWidth = imageData.width;
        const srcHeight = imageData.height;
        const dstWidth = srcWidth * scale;
        const dstHeight = srcHeight * scale;
        const dst = new Uint8ClampedArray(dstWidth * dstHeight * 4);
        for (let y = 0; y < dstHeight; y++) {
          for (let x = 0; x < dstWidth; x++) {
            const dstIdx = (y * dstWidth + x) * 4;
            const srcX = Math.floor(x / scale);
            const srcIdx = (Math.floor(y / scale) * srcWidth + srcX) * 4;
            dst[dstIdx] = src[srcIdx];
            dst[dstIdx + 1] = src[srcIdx + 1];
            dst[dstIdx + 2] = src[srcIdx + 2];
            dst[dstIdx + 3] = src[srcIdx + 3];
          }
        }
        return new ImageData(dst, dstWidth, dstHeight);
      }

      function blur(imageData, topX, topY, blurWidth, blurHeight, radius, iterations) {
        if (Number.isNaN(radius) || radius < 1) {
          throw new Error('Radius is required and must be greater than 0');
        }
        radius = Math.trunc(radius);
        if (Number.isNaN(iterations)) iterations = 1;
        iterations = Math.trunc(iterations);
        if (iterations > 3) iterations = 3;
        if (iterations < 1) iterations = 1;

        const right = blurWidth - 1;
        const bottom = blurHeight - 1;
        const rowBytes = blurWidth << 2;
        const radiusPlusOne = radius + 1;
        const mul = mulTable[radius];
        const shg = shgTable[radius];
        const red = new Int16Array(blurWidth * blurHeight);
        const green = new Int16Array(blurWidth * blurHeight);
        const blue = new Int16Array(blurWidth * blurHeight);
        const minX = new Uint16Array(blurWidth);
        const maxX = new Uint16Array(blurWidth);
        const minY = new Uint16Array(blurHeight);
        const maxY = new Uint16Array(blurHeight);
        const capX = Math.min(right, radius);

        for (let x = 0; x < blurWidth; ++x) {
          minX[x] = Math.min(x + radiusPlusOne, right) << 2;
          maxX[x] = Math.max(x - radius, 0) << 2;
        }
        for (let y = 0; y < blurHeight; ++y) {
          minY[y] = Math.min(y + radiusPlusOne, bottom);
          maxY[y] = Math.max(y - radius, 0);
        }

        const data = new Uint8Array(imageData.data.buffer);
        const pixels = new Uint32Array(data.buffer);

        for (let iter = iterations; -1 !== --iter; ) {
          for (let y = 0, row = 0, flat = 0; y < blurHeight; ++y, row += rowBytes) {
            const rowData = data.subarray(row, rowBytes + row);
            let r = rowData[0] * radiusPlusOne;
            let g = rowData[1] * radiusPlusOne;
            let b = rowData[2] * radiusPlusOne;
            for (let x = 1; x <= capX; ++x) {
              r += rowData[x << 2];
              g += rowData[(x << 2) + 1];
              b += rowData[(x << 2) + 2];
            }
            if (radius > right) {
              r += rowData[rowBytes - 4] * (radius - right);
              g += rowData[rowBytes - 3] * (radius - right);
              b += rowData[rowBytes - 2] * (radius - right);
            }
            for (let x = 0; x < blurWidth; ++x, ++flat) {
              red[flat] = r;
              green[flat] = g;
              blue[flat] = b;
              const add = minX[x];
              const sub = maxX[x];
              if ((pixels[(row + add) >> 2] | pixels[(row + sub) >> 2]) & 0xffffff) {
                r += rowData[add] - rowData[sub];
                g += rowData[add + 1] - rowData[sub + 1];
                b += rowData[add + 2] - rowData[sub + 2];
              }
            }
          }

          for (let x = 0, flatBase = 0; x < blurWidth; flatBase = ++x) {
            let r = red[flatBase] * radiusPlusOne;
            let g = green[flatBase] * radiusPlusOne;
            let b = blue[flatBase] * radiusPlusOne;
            for (let y = 1; y <= radius; y++) {
              if (y <= bottom) flatBase += blurWidth;
              r += red[flatBase];
              g += green[flatBase];
              b += blue[flatBase];
            }
            for (let y = 0, offset = x; y < blurHeight; ++y, offset += blurWidth) {
              const old = pixels[offset];
              if ((b | g | r) === 0) {
                pixels[offset] &= 0xff000000;
              } else {
                pixels[offset] =
                  (pixels[offset] & 0xff000000) |
                  ((b * mul) >> shg) << 16 |
                  ((g * mul) >> shg) << 8 |
                  ((r * mul) >> shg);
              }
              const add = x + minY[y] * blurWidth;
              const sub = x + maxY[y] * blurWidth;
              r += red[add] - red[sub];
              g += green[add] - green[sub];
              b += blue[add] - blue[sub];
            }
          }
        }

        return new ImageData(Uint8ClampedArray.from(data), blurWidth, blurHeight);
      }

      function alphaMatchRed(imageData) {
        const data = new Uint8ClampedArray(imageData.data);
        for (let i = 0; i < data.length; i += 4) {
          data[i + 3] = data[i];
        }
        return new ImageData(data, imageData.width, imageData.height);
      }

      function compose(sourceData, generatedData, maskData) {
        const sourceCanvas = document.createElement('canvas');
        sourceCanvas.width = sourceData.width;
        sourceCanvas.height = sourceData.height;
        const sourceCtx = sourceCanvas.getContext('2d');
        sourceCtx.putImageData(sourceData, 0, 0);

        const generatedCanvas = document.createElement('canvas');
        generatedCanvas.width = sourceData.width;
        generatedCanvas.height = sourceData.height;
        const generatedCtx = generatedCanvas.getContext('2d');
        generatedCtx.putImageData(generatedData, 0, 0);

        const maskCanvas = document.createElement('canvas');
        maskCanvas.width = sourceData.width;
        maskCanvas.height = sourceData.height;
        maskCanvas.getContext('2d').putImageData(maskData, 0, 0);

        generatedCtx.globalCompositeOperation = 'destination-in';
        generatedCtx.drawImage(maskCanvas, 0, 0);

        sourceCtx.drawImage(generatedCanvas, 0, 0);
        return sourceCtx.getImageData(0, 0, sourceData.width, sourceData.height);
      }

      const [
        sourceImage,
        generatedImage,
        maskImage,
        localCompositeMaskImage,
      ] = await Promise.all([
        loadImage(sourceUrl),
        loadImage(generatedUrl),
        loadImage(maskUrl),
        loadImage(localCompositeMaskUrl),
      ]);
      const sourceData = imageToData(sourceImage);
      const generatedData = imageToData(generatedImage);
      const maskData = imageToData(maskImage);
      const localCompositeMaskData = imageToData(localCompositeMaskImage);

      const latent = thresholdAlpha(
        resizeCanvas(maskData, width / 8, height / 8, false),
        155,
      );
      const requestMask = resizeOverBlack(latent, width, height, false);
      const compositeMask = alphaMatchRed(
        blur(
          linearScale(dilate(replaceTransparent(latent, [0, 0, 0, 255]), 4, latent.width, latent.height), 8),
          0,
          0,
          width,
          height,
          20,
          2,
        ),
      );
      const finalImage = compose(sourceData, generatedData, compositeMask);
      const finalWithLocalMask = compose(
        sourceData,
        generatedData,
        alphaMatchRed(localCompositeMaskData),
      );

      return {
        requestMask: dataToPngBase64(requestMask),
        compositeMask: dataToPngBase64(compositeMask),
        finalImage: dataToPngBase64(finalImage),
        finalWithLocalMask: dataToPngBase64(finalWithLocalMask),
      };
    },
    {
      sourceUrl: readDataUrl('source.png'),
      generatedUrl: readDataUrl('generated.png'),
      maskUrl: readDataUrl('mask_alpha.png'),
      localCompositeMaskUrl: readDataUrl('local_composite_mask_bw.png'),
      width,
      height,
    },
  );
  await browser.close();

  writeBase64Png('official_request_mask.png', official.requestMask);
  writeBase64Png('official_composite_mask.png', official.compositeMask);
  writeBase64Png('official_final.png', official.finalImage);
  writeBase64Png(
    'browser_final_with_local_mask.png',
    official.finalWithLocalMask,
  );

  const comparisons = [
    comparePngs(
      'local_request_mask_bw.png',
      'official_request_mask.png',
      'diff_request_mask_bw_vs_official.png',
    ),
    comparePngs(
      'local_request_mask_alpha.png',
      'local_request_mask_bw.png',
      'diff_request_mask_alpha_vs_bw.png',
    ),
    comparePngs(
      'local_composite_mask_bw.png',
      'official_composite_mask.png',
      'diff_composite_mask_bw_vs_official.png',
    ),
    comparePngs(
      'local_composite_mask_alpha.png',
      'local_composite_mask_bw.png',
      'diff_composite_mask_alpha_vs_bw.png',
    ),
    comparePngs(
      'local_final_bw.png',
      'official_final.png',
      'diff_final_bw_vs_official.png',
    ),
    comparePngs(
      'local_final_alpha.png',
      'local_final_bw.png',
      'diff_final_alpha_vs_bw.png',
    ),
    comparePngs(
      'browser_final_with_local_mask.png',
      'official_final.png',
      'diff_browser_local_mask_vs_official_final.png',
    ),
    comparePngs(
      'local_final_bw.png',
      'browser_final_with_local_mask.png',
      'diff_local_final_vs_browser_local_mask.png',
    ),
  ];

  if (fs.existsSync(path.join(outputDir, 'local_final_with_official_mask.png'))) {
    comparisons.push(
      comparePngs(
        'local_final_with_official_mask.png',
        'official_final.png',
        'diff_local_official_mask_vs_official_final.png',
      ),
    );
  }

  const summary = {
    outputDir,
    officialReference: {
      page: 'https://novelai.net/image',
      imageChunk: 'https://novelai.net/_next/static/chunks/9034-4efe253183f30e2c.js',
      workerChunk: 'https://novelai.net/_next/static/chunks/409.153df816a4833192.js',
    },
    comparisons,
  };

  fs.writeFileSync(
    path.join(outputDir, 'parity_summary.json'),
    `${JSON.stringify(summary, null, 2)}\n`,
  );
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
