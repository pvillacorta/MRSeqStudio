const path = require('path');
const HtmlWebpackPlugin = require('html-webpack-plugin');
const { CleanWebpackPlugin } = require('clean-webpack-plugin');
const TerserPlugin = require('terser-webpack-plugin');
const { ProgressPlugin } = require('webpack');
const CopyPlugin = require('copy-webpack-plugin');

module.exports = (env, argv) => {
    const isProduction = argv.mode === 'production';

    return {
        entry: {
            index: './src/index.js',
            login: './src/login.js',
        },
        module: {
            rules: [
                {
                    test: /\.css$/i,
                    use: ["style-loader", "css-loader"],
                    exclude: /node_modules/,
                },
            ],
        },
        resolve: {
            extensions: ['.js'],
        },
        output: {
            filename: '[name].js',
            path: path.resolve(__dirname, 'dist'),
            clean: false,
        },
        optimization: {
            minimize: isProduction,
            minimizer: [new TerserPlugin()],
        },
        plugins: [
            new ProgressPlugin(),
            new CleanWebpackPlugin(),
            new HtmlWebpackPlugin({
                template: 'src/index.html',
                filename: 'index.html',
                chunks: ['index'],
            }),
            new HtmlWebpackPlugin({
                template: 'src/login.html',
                filename: 'login.html',
                chunks: ['login'],
            }),
            new HtmlWebpackPlugin({
                template: 'src/register.html',
                filename: 'register.html',
                chunks: ['login'],
            }),
            new CopyPlugin({
                patterns: [
                    { from: 'src/utils_private.js', to: '.' },
                    { from: 'src/assets', to: 'assets' },
                    { from: 'node_modules/@itk-wasm/image-io/dist/pipelines/*.{js,wasm,wasm.zst}', to: 'pipelines/[name][ext]' }
                ],
            }),
        ],
        devServer: {
            static: {
                directory: '../public',
                publicPath: '/public',
            }
        },
        devtool: 'source-map',
    };
};
