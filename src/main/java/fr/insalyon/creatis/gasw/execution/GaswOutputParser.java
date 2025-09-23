/* Copyright CNRS-CREATIS
 *
 * Rafael Ferreira da Silva
 * rafael.silva@creatis.insa-lyon.fr
 * http://www.rafaelsilva.com
 *
 * This software is governed by the CeCILL  license under French law and
 * abiding by the rules of distribution of free software.  You can  use,
 * modify and/ or redistribute the software under the terms of the CeCILL
 * license as circulated by CEA, CNRS and INRIA at the following URL
 * "http://www.cecill.info".
 *
 * As a counterpart to the access to the source code and  rights to copy,
 * modify and redistribute granted by the license, users are provided only
 * with a limited warranty  and the software's author,  the holder of the
 * economic rights,  and the successive licensors  have only  limited
 * liability.
 *
 * In this respect, the user's attention is drawn to the risks associated
 * with loading,  using,  modifying and/or developing or reproducing the
 * software by the user in light of its specific status of free software,
 * that may mean  that it is complicated to manipulate,  and  that  also
 * therefore means  that it is reserved for developers  and  experienced
 * professionals having in-depth computer knowledge. Users are therefore
 * encouraged to load and test the software's suitability as regards their
 * requirements in conditions enabling the security of their systems and/or
 * data to be ensured and,  more generally, to use and operate it in the
 * same conditions as regards security.
 *
 * The fact that you are presently reading this means that you have had
 * knowledge of the CeCILL license and that you accept its terms.
 */
package fr.insalyon.creatis.gasw.execution;

import fr.insalyon.creatis.gasw.*;
import fr.insalyon.creatis.gasw.bean.*;
import fr.insalyon.creatis.gasw.dao.DAOException;
import fr.insalyon.creatis.gasw.dao.DAOFactory;
import fr.insalyon.creatis.gasw.plugin.ListenerPlugin;
import java.io.*;
import java.net.URI;
import java.util.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class GaswOutputParser extends Thread {

    private static final Logger logger = LoggerFactory.getLogger(GaswOutputParser.class);
    protected Job job;
    protected File appStdOut;
    protected File appStdErr;
    protected BufferedWriter appStdOutWriter;
    protected BufferedWriter appStdErrWriter;
    protected List<Data> dataList;
    protected Map<String, URI> uploadedResults;
    protected StringBuilder inputsDownloadErrBuf;
    protected StringBuilder resultsUploadErrBuf;
    protected StringBuilder appStdOutBuf;
    protected StringBuilder appStdErrBuf;

    public GaswOutputParser(String jobID) {
        try {
            this.job = DAOFactory.getDAOFactory().getJobDAO().getJobByID(jobID);

            this.appStdOut = getAppStdFile(GaswConstants.OUT_APP_EXT, GaswConstants.OUT_ROOT);
            this.appStdErr = getAppStdFile(GaswConstants.ERR_APP_EXT, GaswConstants.ERR_ROOT);

            this.appStdOutWriter = new BufferedWriter(new FileWriter(appStdOut));
            this.appStdErrWriter = new BufferedWriter(new FileWriter(appStdErr));

            this.inputsDownloadErrBuf = new StringBuilder();
            this.resultsUploadErrBuf = new StringBuilder();
            this.appStdOutBuf = new StringBuilder();
            this.appStdErrBuf = new StringBuilder();

            this.dataList = new ArrayList<Data>();
            this.uploadedResults = null;

        } catch (IOException | DAOException ex) {
            closeBuffers();
            logger.error("Error creating std out/err " +
                    "files and buffers for {}", jobID, ex);
        }
    }

    private void closeBuffers() {
        try {
            if (appStdOutWriter != null) {
                appStdOutWriter.close();
            }
            if (appStdErrWriter != null) {
                appStdErrWriter.close();
            }
        } catch (IOException ex) {
            logger.error("Error closing buffers", ex);
        }
    }

    @Override
    public void run() {
        try {
            GaswOutput gaswOutput = getGaswOutput();

            for (ListenerPlugin listener : GaswConfiguration.getInstance().getListenerPlugins()) {
                try {
                    listener.jobFinished(gaswOutput);
                } catch (Exception ex) {
                    logger.warn("Error ", ex);
                }
            }
            // the job is marked as replicating, because it could be
            // replicated in case of error
            // remove this flag if it is not replicated after all
            try {
                // do not resubmit a job that was deliberately cancelled/killed
                if (gaswOutput.getExitCode() == GaswExitCode.SUCCESS || gaswOutput.getExitCode() == GaswExitCode.EXECUTION_CANCELED || job.isBeingKilled()) {
                    job.setReplicating(false);
                    DAOFactory.getDAOFactory().getJobDAO().update(job);
                } else {
                    int retries = DAOFactory.getDAOFactory().getJobDAO().getFailedJobsByInvocationID(job.getInvocationID()).size() - 1;
                    if (retries < GaswConfiguration.getInstance().getDefaultRetryCount()) {
                        logger.warn("Job [{}] finished as \"{}\" (retried {} times).", job.getId(), job.getStatus().name(), retries);
                        resubmit();
                    } else {
                        logger.warn("Job [{}] finished as \"{}\": holding job (max retries reached).", job.getId(), job.getStatus().name());
                        if (job.getStatus() == GaswStatus.ERROR) {
                            job.setStatus(GaswStatus.ERROR_HELD);
                        } else if (job.getStatus() == GaswStatus.STALLED) {
                            job.setStatus(GaswStatus.STALLED_HELD);
                        }
                        job.setReplicating(false);
                        DAOFactory.getDAOFactory().getJobDAO().update(job);
                    }
                    GaswNotification.getInstance().addErrorJob(gaswOutput);
                    return;
                }
            } catch (DAOException | GaswException ex) {
                logger.error("Error finalising job {}", job.getId(), ex);
            }
            GaswNotification.getInstance().addFinishedJob(gaswOutput);

        } catch (GaswException ex) {
            logger.error("Error processing output for job {}", job.getId(), ex);
        }
    }

    /**
     * Gets the standard output and error files and exit code.
     *
     * @return Gasw output object with the standard output and error files
     * respectively.
     * @throws GaswException
     */
    public abstract GaswOutput getGaswOutput() throws GaswException;

    protected abstract void resubmit() throws GaswException;

    /**
     * We use synchronized keyword in case of multiples jobs ending together (at the same time),
     * it cause an issue if hibernate try to merge/add the same job inside the db
     */
    protected int parseStdOut(File stdOut) {
        int exitCode = -1;

        try {
            if (job.getQueued() == null) {
                job.setQueued(job.getCreation());
            }
            if (job.getDownload() == null) {
                job.setDownload(job.getQueued());
            }

            Node node = new Node();
            NodeID nodeID = new NodeID();
            Scanner scanner = new Scanner(new FileInputStream(stdOut));

            boolean isAppExec = false;
            boolean isInputDownload = false;
            boolean isResultUpload = false;
            boolean isAfterExec = false;
            String lfcHost = "";

            try {
                while (scanner.hasNextLine()) {

                    String line = scanner.nextLine();
                    String[] lineSplitted = line.split(" ");

                    // Application Output
                    if (line.contains("<application_execution>")) {
                        isAppExec = true;
                    } else if (line.contains("</application_execution>")) {
                        isAppExec = false;
                        isAfterExec = true;
                    } else if (isAppExec) {
                        appStdOutWriter.write(line + "\n");
                        appStdOutBuf.append(line).append("\n");
                    }

                    // General Output
                    if (line.contains("Input download time:")) {
                        int downloadTime = Integer.parseInt(lineSplitted[lineSplitted.length - 2]);
                        job.setRunning(addDate(job.getDownload(), Calendar.SECOND, downloadTime));

                    } else if (line.contains("Execution time:")) {

                        if (job.getRunning() == null) {
                            job.setRunning(job.getDownload());
                        }
                        int executionTime = Integer.parseInt(lineSplitted[lineSplitted.length - 2]);
                        job.setUpload(addDate(job.getRunning(), Calendar.SECOND, executionTime));

                    } else if (line.contains("Results upload time:")) {
                        int uploadTime = Integer.parseInt(lineSplitted[lineSplitted.length - 2]);
                        job.setEnd(addDate(job.getUpload(), Calendar.SECOND, uploadTime));

                    } else if (line.contains("Exiting with return value") && isAfterExec) {
                        String[] errmsg = line.split("\\s+");
                        exitCode = Integer.parseInt(errmsg[errmsg.length - 1]);
                        job.setExitCode(exitCode);

                    } else if (line.startsWith("===== uname =====")) {
                        line = scanner.nextLine();
                        nodeID.setNodeName(line.split(" ")[1]);

                    } else if (line.startsWith("SITE_NAME")) {
                        nodeID.setSiteName(line.split("=")[1]);

                    } else if (line.startsWith("PBS_O_HOST") && nodeID.getSiteName() == null) {
                        nodeID.setSiteName(line.split("=")[1]);
                        String code = nodeID.getNodeName().substring(nodeID.getNodeName().lastIndexOf(".") + 1);
                        if (code.length() != 2) {
                            String host = line.split("=")[1];
                            String countryCode = host.substring(host.lastIndexOf("."));
                            nodeID.setNodeName(nodeID.getNodeName() + countryCode);
                        }

                    } else if (line.startsWith("CE_ID")) {
                        String code = nodeID.getNodeName().substring(nodeID.getNodeName().lastIndexOf(".") + 1);
                        if (code.length() != 2) {
                            String host = URI.create("http://" + line.split("=")[1]).getHost();
                            String countryCode = host.substring(host.lastIndexOf("."));
                            nodeID.setNodeName(nodeID.getNodeName() + countryCode);
                        }

                    } else if (line.startsWith("processor")) {
                        node.setnCpus(Integer.parseInt(line.split(":")[1].trim()) + 1);

                    } else if (line.startsWith("model name")) {
                        node.setCpuModelName(line.split(":")[1].trim());

                    } else if (line.startsWith("cpu MHz")) {
                        node.setCpuMhz(Double.parseDouble(line.split(":")[1].trim()));

                    } else if (line.startsWith("cache size")) {
                        node.setCpuCacheSize(Integer.parseInt(line.split(":")[1].trim().split(" ")[0]));

                    } else if (line.startsWith("bogomips")) {
                        node.setCpuBogoMips(Double.parseDouble(line.split(":")[1].trim()));

                    } else if (line.startsWith("MemTotal:")) {
                        node.setMemTotal(Integer.parseInt(line.split("\\s+")[1]));

                    } else if (line.startsWith("<inputs_download>")) {
                        isInputDownload = true;

                    } else if (line.startsWith("</inputs_download>")) {
                        isInputDownload = false;

                    } else if (line.startsWith("<file_download") && isInputDownload) {
                        String downloadedFile = line.substring(line.indexOf("=") + 1, line.length() - 1);
                        dataList.add(new Data(downloadedFile, Data.Type.Input));
                        logger.info("Adding input {} for job {}", downloadedFile, job.getId());

                    } else if (line.startsWith("<results_upload>")) {
                        isResultUpload = true;
                        uploadedResults = new HashMap<String, URI>();

                    } else if (line.startsWith("</results_upload>")) {
                        isResultUpload = false;

                    } else if (line.startsWith("LFC_HOST")) {
                        lfcHost = line.substring(line.indexOf("=") + 1);

                    } else if (line.startsWith("<file_upload") && isResultUpload) {
                        int uriStartIndex = line.lastIndexOf("uri=");
                        // the output is like this <file upload id= uri= >
                        String outputId = line.substring(line.indexOf("id=") + 3, uriStartIndex - 1);
                        String uploadedFile = line.substring(uriStartIndex + 4, line.length() - 1);
                        URI uri;
                        if (GaswUtil.isUri(uploadedFile)) {
                            uri = new URI(uploadedFile);
                        } else {
                            uri = lfcHost.isEmpty()
                                ? new URI("file://" + uploadedFile)
                                : new URI("lfn://" + lfcHost + uploadedFile);
                        }
                        uploadedResults.put(outputId, uri);
                        dataList.add(new Data(uri.toString(), Data.Type.Output));
                        logger.info("Adding output {} {} for job {}" + outputId, uri, job.getId());
                    }
                }
            } catch (Exception ex) {
                logger.error("Error parsing stdout {}", stdOut.getAbsolutePath(), ex);
            } finally {
                scanner.close();
            }
            appStdOutWriter.close();

            DAOFactory factory = DAOFactory.getDAOFactory();
            if (nodeID.getSiteName() != null && nodeID.getNodeName() != null) {
                node.setNodeID(nodeID);
                factory.getNodeDAO().add(node);
                job.setNode(node);
            }

            // Parse checkpoint
            parseCheckpoint();

            // Update Job
            job.setData(dataList);
            if (job.getEnd() == null) {
                job.setEnd(new Date());
            }

            factory.getJobDAO().update(job);

        } catch (DAOException | IOException ex) {
            closeBuffers();
            logger.error("Error parsing stdout {}", stdOut.getAbsolutePath(), ex);
        }
        return exitCode;
    }

    protected int parseStdErr(File stdErr, int exitCode) {
        try {
            Scanner scanner = new Scanner(new FileInputStream(stdErr));

            try {
                boolean isAppExec = false;
                boolean isInputsDownload = false;
                boolean isResultsUpload = false;
                boolean isUploadTest = false;

                while (scanner.hasNext()) {

                    String line = scanner.nextLine();

                    // Application Error
                    if (line.contains("<application_execution>")) {
                        isAppExec = true;

                    } else if (line.contains("</application_execution>")) {
                        isAppExec = false;

                    } else if (line.contains("<inputs_download>")) {
                        isInputsDownload = true;

                    } else if (line.contains("</inputs_download>")) {
                        isInputsDownload = false;

                    } else if (line.contains("<results_upload>")) {
                        isResultsUpload = true;

                    } else if (line.contains("</results_upload>")) {
                        isResultsUpload = false;

                    } else if (line.contains("<upload_test>")) {
                        isUploadTest = true;

                    } else if (line.contains("</upload_test>")) {
                        isUploadTest = false;

                    } else if (isAppExec) {
                        appStdErrWriter.write(line + "\n");
                        appStdErrBuf.append(line).append("\n");

                    } else if (isInputsDownload) {
                        inputsDownloadErrBuf.append(line).append("\n");

                    } else if (isResultsUpload) {
                        resultsUploadErrBuf.append(line).append("\n");

                    } else if (isUploadTest) {
                        resultsUploadErrBuf.append(line).append("\n");
                    }

                    if (line.contains("Exiting with return value")) {
                        String[] errmsg = line.split("\\s+");
                        exitCode = Integer.valueOf(errmsg[errmsg.length - 1]).intValue();
                        job.setExitCode(exitCode);
                    }
                }
            } finally {
                scanner.close();
            }
            appStdErrWriter.close();
            DAOFactory.getDAOFactory().getJobDAO().update(job);

        } catch (DAOException | IOException ex) {
            closeBuffers();
            logger.error("Error parsing stderr {}", stdErr.getAbsolutePath(), ex);

        }
        return exitCode;
    }

    protected void parseNonStdOut(int exitCode) {

        try {
            job.setEnd(new Date());
            DAOFactory factory = DAOFactory.getDAOFactory();

            for (JobMinorStatus minorStatus : factory.getJobMinorStatusDAO().getExecutionMinorStatus(job.getId())) {
                switch (minorStatus.getStatus()) {
                    case Application:
                        job.setRunning(minorStatus.getDate());
                        break;
                    case Outputs:
                        job.setUpload(minorStatus.getDate());
                }
            }
            parseCheckpoint();
            job.setExitCode(exitCode);
            factory.getJobDAO().update(job);

        } catch (DAOException ex) {
            closeBuffers();
            logger.error("Error parsing NonStdOut", ex);
        }
    }

    private void parseCheckpoint() {

        try {
            DAOFactory factory = DAOFactory.getDAOFactory();

            List<JobMinorStatus> list = factory.getJobMinorStatusDAO().getCheckpoints(job.getId());

            if (!list.isEmpty()) {
                int sumCheckpointInit = 0;
                int sumCheckpointUpload = 0;
                long startCheckpoint = -1;
                long startUpload = -1;

                for (JobMinorStatus minorStatus : list) {

                    if (minorStatus.getStatus() == GaswMinorStatus.CheckPoint_Init) {
                        startCheckpoint = minorStatus.getDate().getTime();

                    } else if (minorStatus.getStatus() == GaswMinorStatus.CheckPoint_Upload
                            && startCheckpoint != -1) {

                        startUpload = minorStatus.getDate().getTime();
                        sumCheckpointInit += (int) (startUpload - startCheckpoint) / 1000;
                        startCheckpoint = -1;

                    } else if (minorStatus.getStatus() == GaswMinorStatus.CheckPoint_End
                            && startUpload != -1) {

                        sumCheckpointUpload += (int) (minorStatus.getDate().getTime() - startUpload) / 1000;
                        startUpload = -1;
                    }
                }

                job.setCheckpointInit(sumCheckpointInit);
                job.setCheckpointUpload(sumCheckpointUpload);
            }
        } catch (DAOException ex) {
            closeBuffers();
            logger.error("Error parsing checkpoints", ex);
        }
    }

    protected File saveFile(String extension, String dir, String content) {
        FileWriter fstream = null;
        try {
            File stdDir = new File(dir);
            if (!stdDir.exists()) {
                stdDir.mkdir();
            }
            File stdFile = new File(dir + "/" + job.getFileName() + ".sh" + extension);
            fstream = new FileWriter(stdFile);
            BufferedWriter out = new BufferedWriter(fstream);
            out.write(content);
            out.close();

            return stdFile;

        } catch (IOException ex) {
            logger.error("Error:", ex);
        } finally {
            try {
                fstream.close();
            } catch (IOException ex) {
                logger.error("Error:", ex);
            }
        }
        return null;
    }

    protected File moveAppFile(File source, String extension, String dir) {
        File dest = getAppStdFile(extension, dir);
        if (source.exists()) {
            source.renameTo(dest);
        } else {
            logger.warn("Missing output file : " + source);
        }
        return dest;
    }

    protected File moveProvenanceFile(String sourceDir) {
        String provenanceFileName = getAppStdFileName(GaswConstants.PROVENANCE_EXT);
        return moveAppFile(
                new File(sourceDir, provenanceFileName),
                GaswConstants.PROVENANCE_EXT,
                GaswConstants.PROVENANCE_ROOT);
    }

    protected File getAppStdFile(String extension, String dir) {
        File stdDir = new File(dir);

        if (!stdDir.exists()) {
            stdDir.mkdirs();
        }
        return new File(dir + "/" + getAppStdFileName(extension));
    }

    protected String getAppStdFileName(String extension) {
        return job.getFileName() + ".sh" + extension;
    }

    protected String getInputsDownloadErr() {
        return inputsDownloadErrBuf.toString();
    }

    protected String getResultsUploadErr() {
        return resultsUploadErrBuf.toString();
    }

    protected String getAppStdErr() {
        return appStdErrBuf.toString();
    }

    protected String getAppStdOut() {
        return appStdOutBuf.toString();
    }

    private Date addDate(Date dateToBeAdded, int field, int amount) {

        Calendar calendar = Calendar.getInstance();
        calendar.setTime(dateToBeAdded);
        calendar.add(field, amount);
        return calendar.getTime();
    }
}
