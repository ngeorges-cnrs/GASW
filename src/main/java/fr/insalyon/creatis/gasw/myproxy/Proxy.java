package fr.insalyon.creatis.gasw.myproxy;

import fr.insalyon.creatis.gasw.ProxyRetrievalException;
import fr.insalyon.creatis.gasw.VOMSExtensionAppendException;
import java.io.File;
import java.io.IOException;
import org.apache.log4j.Logger;

/**
 *
 * @author Tram Truong Huu
 */
public abstract class Proxy {

    private static final Logger log = Logger.getLogger(Proxy.class);
    private static final int DEFAULT_DELEGATED_PROXY_LIFETIME = 24; //24 hours
    protected static final int MIN_LIFETIME_FOR_USING = 1;   //  hours
    protected GaswUserCredentials gaswCredentials;
    protected int lifetime; // in hours
    protected MyProxyServer proxyServer;
    protected File proxyFile;

    public Proxy(GaswUserCredentials credentials) {
        this.gaswCredentials = credentials;
        this.lifetime = DEFAULT_DELEGATED_PROXY_LIFETIME;
        this.proxyServer = credentials.getMyproxyServer();
        this.proxyFile = null;
    }

    public void initRawProxy() throws ProxyRetrievalException {
        initRawProxy(DEFAULT_DELEGATED_PROXY_LIFETIME);
    }

    public void initRawProxy(int lifetime) throws ProxyRetrievalException {

        if (lifetime < MIN_LIFETIME_FOR_USING) {
            lifetime = DEFAULT_DELEGATED_PROXY_LIFETIME;
        }
        this.lifetime = lifetime;

        if (this.proxyFile != null) {
            this.proxyFile.delete();
        }
        try {
            this.proxyFile = File.createTempFile("gasw_", ".proxy");
            myProxyLogon(this.proxyFile);
        } catch (IOException ex) {
            throw new ProxyRetrievalException("Cannot create temporary file to store proxy: " + ex.getMessage());
        }
    }

    public void init() throws ProxyRetrievalException, VOMSExtensionAppendException {
        init(DEFAULT_DELEGATED_PROXY_LIFETIME);
    }

    public void init(int lifetime) throws ProxyRetrievalException, VOMSExtensionAppendException {

        if (lifetime < MIN_LIFETIME_FOR_USING) {
            lifetime = DEFAULT_DELEGATED_PROXY_LIFETIME;
        }
        this.lifetime = lifetime;

        if (this.proxyFile != null) {
            this.proxyFile.delete();
        }

        try {
            proxyFile = File.createTempFile("gasw_", ".proxy");
            myProxyLogon(proxyFile);
            vomsProxyInit(proxyFile);

        } catch (IOException ex) {
            throw new ProxyRetrievalException("Cannot create temporary file to store proxy: " + ex.getMessage());
        }
    }

    public File getProxy() {
        return proxyFile;
    }

    /**
     * Check the validity of proxy including voms extension
     * @return true if remaining life time is greater than a default threshold, false otherwise
     */
    public abstract boolean isValid();

    /**
     * Check the validity of proxy without voms extension
     * @return true if remaining life time is greater than a default threshold, false otherwise
     */
    public abstract boolean isRawProxyValid();

    /**
     * Download a raw proxy from myProxy Server
     * @param proxyFile file to store proxy
     * @throws ProxyRetrievalException 
     */
    protected abstract void myProxyLogon(File proxyFile) throws ProxyRetrievalException;

    /**
     * Append VOMS Extension to an existing raw proxy
     * @param proxyFile
     * @throws VOMSExtensionAppendException 
     */
    protected abstract void vomsProxyInit(File proxyFile) throws VOMSExtensionAppendException;
}
