// Minimal EmbedLite browser shell: sets up the embedding context the way
// qtmozembed's test runner does, then shows main.qml.
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQmlContext>
#include <QTextStream>
#include <QQuickView>
#include <QTimer>
#include <qmozcontext.h>
#include <qmozenginesettings.h>

static const char kComponents[] = "/usr/lib/arm-linux-gnueabihf/mozembedlite-next153";
static const char kProfile[] = "embedlite-shell";

// Prefs Gecko reads once at startup, in the profile's user.js: WebRender
// on the GPU (the SGX530 through its OpenGL ES 2.0 path) with compiled
// shader programs kept on disk, and edge anti-aliasing unless --no-edge-aa
// (jagged rotated edges, three times faster rotated content).
static void writeUserPrefs(bool edgeAa)
{
    const QString dir = QDir::homePath() + "/.mozilla/" + kProfile;
    QDir().mkpath(dir);
    QFile file(dir + "/user.js");
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return;
    QTextStream out(&file);
    out << "user_pref(\"gfx.webrender.all\", true);\n"
        << "user_pref(\"gfx.webrender.software\", false);\n"
        << "user_pref(\"gfx.webrender.program-binary-disk\", true);\n"
        << "user_pref(\"gfx.webrender.edge-aa\", " << (edgeAa ? "true" : "false") << ");\n";
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QString start = QStringLiteral("about:blank");
    bool edgeAa = true;
    for (const QString &arg : app.arguments().mid(1)) {
        if (arg == QLatin1String("--no-edge-aa"))
            edgeAa = false;
        else
            start = arg;
    }
    writeUserPrefs(edgeAa);

    QMozContext *context = QMozContext::instance();
    context->setProfile(QString::fromLatin1(kProfile));
    const QString components = QString::fromLatin1(kComponents);
    context->addComponentManifest(components + "/components/EmbedLiteBinComponents.manifest");
    context->addComponentManifest(components + "/chrome/EmbedLiteJSScripts.manifest");
    context->addComponentManifest(components + "/chrome/EmbedLiteOverrides.manifest");
    context->addComponentManifest(components + "/components/EmbedLiteJSComponents.manifest");
    QObject::connect(context, &QMozContext::lastViewDestroyed, context, &QMozContext::stopEmbedding);
    QObject::connect(context, &QMozContext::contextDestroyed, &app, &QGuiApplication::quit);

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty(QStringLiteral("startUrl"), start);

    QTimer::singleShot(0, [&] {
        context->runEmbedding();
        QMozEngineSettings::instance();
        view.setSource(QUrl(QStringLiteral("qrc:/main.qml")));
        view.showFullScreen();
    });
    return app.exec();
}
